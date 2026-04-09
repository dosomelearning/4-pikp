#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"

# Runtime inputs (overridable) for source paths and logging cadence.
ACCIDENTS_CSV="${ACCIDENTS_CSV:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
AIR_DIR="${AIR_DIR:-${ROOT_DIR}/raw}"
AIR_START_YEAR="${AIR_START_YEAR:-2016}"
AIR_END_YEAR="${AIR_END_YEAR:-2023}"
RULES_JSON="${RULES_JSON:-${ROOT_DIR}/scripts/analysis/rules.json}"
PROGRESS_EVERY_ACCIDENTS="${PROGRESS_EVERY_ACCIDENTS:-250000}"
PROGRESS_EVERY_AIR="${PROGRESS_EVERY_AIR:-50000}"
TOP_ISSUES="${TOP_ISSUES:-10}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  exit 1
fi

if [[ ! -f "${ACCIDENTS_CSV}" ]]; then
  echo "ERROR: raw accidents CSV not found: ${ACCIDENTS_CSV}"
  exit 1
fi

if [[ ! -d "${AIR_DIR}" ]]; then
  echo "ERROR: air directory not found: ${AIR_DIR}"
  exit 1
fi

if [[ ! -f "${RULES_JSON}" ]]; then
  echo "ERROR: rules file not found: ${RULES_JSON}"
  exit 1
fi

if [[ "${AIR_START_YEAR}" -gt "${AIR_END_YEAR}" ]]; then
  echo "ERROR: AIR_START_YEAR must be <= AIR_END_YEAR"
  echo "  AIR_START_YEAR=${AIR_START_YEAR}"
  echo "  AIR_END_YEAR=${AIR_END_YEAR}"
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

# Temp TSV produced by Python and fed into COPY.
TMP_VALUES_FILE="$(mktemp)"
trap 'rm -f "${TMP_VALUES_FILE}"' EXIT

echo "Scanning v2 county members from accidents + air sources"
echo "started_at: ${RUN_START_HUMAN}"
echo "accidents_csv: ${ACCIDENTS_CSV}"
echo "air_dir: ${AIR_DIR}"
echo "air_year_range: ${AIR_START_YEAR}-${AIR_END_YEAR}"
echo "rules_json: ${RULES_JSON}"
echo "progress_every_accidents: ${PROGRESS_EVERY_ACCIDENTS}"
echo "progress_every_air: ${PROGRESS_EVERY_AIR}"
echo "top_issues: ${TOP_ISSUES}"

python - \
  "${ACCIDENTS_CSV}" \
  "${AIR_DIR}" \
  "${AIR_START_YEAR}" \
  "${AIR_END_YEAR}" \
  "${RULES_JSON}" \
  "${PROGRESS_EVERY_ACCIDENTS}" \
  "${PROGRESS_EVERY_AIR}" \
  "${TOP_ISSUES}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import json
import re
import sys
from collections import Counter
from pathlib import Path

accidents_csv = Path(sys.argv[1])
air_dir = Path(sys.argv[2])
air_start_year = int(sys.argv[3])
air_end_year = int(sys.argv[4])
rules_json = Path(sys.argv[5])
progress_every_acc = int(sys.argv[6])
progress_every_air = int(sys.argv[7])
top_issues = int(sys.argv[8])

space_re = re.compile(r"\s+")


# Shared canonicalization helpers keep NK construction deterministic.
def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None


def normalize_state_code(raw):
    value = canon(raw)
    return value.upper() if value else None


def normalize_country_code(raw):
    value = canon(raw)
    return value.upper() if value else None


def normalize_county_name(raw):
    value = canon(raw)
    if value is None:
        return None
    words = value.split(" ")
    out = []
    for w in words:
        wl = w.lower()
        if wl in ("st", "st."):
            out.append("Saint")
        elif wl in ("ste", "ste."):
            out.append("Sainte")
        else:
            out.append(w)
    return " ".join(out)


def normalize_county_code(raw):
    value = canon(raw)
    if value is None:
        return None
    if value.isdigit() and len(value) <= 3:
        return value.zfill(3)
    return value


def county_nk(county_name, state_code, country_code):
    return "C|" + "|".join([county_name, state_code, country_code])


def tsv(value):
    if value is None:
        return r"\N"
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


with rules_json.open("r", encoding="utf-8") as f:
    rules = json.load(f)

raw_map = rules.get("air", {}).get("state_name_to_abbrev", {})
state_name_to_abbrev = {k.strip().lower(): v.strip().upper() for k, v in raw_map.items() if k and v}
excluded_state_names = {
    (x or "").strip().lower()
    for x in rules.get("air", {}).get("exclude_state_names", [])
    if (x or "").strip()
}

if not state_name_to_abbrev:
    raise RuntimeError("Rules missing: air.state_name_to_abbrev must be populated in scripts/analysis/rules.json")

county_members = {}
code_name_counter = {}

# Pass 1: seed county members from accidents (name/state/country path).
acc_rows = 0
acc_added = 0
acc_skipped_missing = 0

with accidents_csv.open(newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        acc_rows += 1
        county_name = normalize_county_name(row.get("County"))
        state_code = normalize_state_code(row.get("State"))
        country_code = normalize_country_code(row.get("Country"))
        if county_name is None or state_code is None or country_code is None:
            acc_skipped_missing += 1
            continue

        nk = county_nk(county_name, state_code, country_code)
        if nk not in county_members:
            county_members[nk] = {
                "county_name": county_name,
                "state_code": state_code,
                "country_code": country_code,
                "source_county_code": None,
            }
            acc_added += 1

        if progress_every_acc > 0 and acc_rows % progress_every_acc == 0:
            print(
                (
                    f"[progress][accidents] rows={acc_rows:,} "
                    f"county_members={len(county_members):,} "
                    f"added={acc_added:,} skipped_missing={acc_skipped_missing:,}"
                ),
                file=sys.stderr,
                flush=True,
            )

air_rows = 0
air_files_found = 0
air_missing_files = 0
air_skipped_missing = 0
air_skipped_excluded_state = 0
air_code_rows = 0
air_name_conflicts = 0

# Pass 2: collect code-backed county identity from yearly air files.
for year in range(air_start_year, air_end_year + 1):
    csv_path = air_dir / f"daily_aqi_by_county_{year}.csv"
    if not csv_path.exists():
        air_missing_files += 1
        print(f"[warn][air] missing_file={csv_path}", file=sys.stderr, flush=True)
        continue

    air_files_found += 1
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            air_rows += 1

            county_name = normalize_county_name(row.get("county Name") or row.get("County Name"))
            state_name = canon(row.get("State Name"))
            state_name_key = state_name.lower() if state_name else None
            state_abbrev = state_name_to_abbrev.get(state_name_key) if state_name_key else None
            source_state_code = normalize_county_code(row.get("State Code"))
            source_county_code = normalize_county_code(row.get("County Code"))

            if state_name_key in excluded_state_names:
                air_skipped_excluded_state += 1
                continue
            if county_name is None or state_abbrev is None or source_state_code is None or source_county_code is None:
                air_skipped_missing += 1
                continue

            code_key = ("US", state_abbrev, source_county_code)
            bucket = code_name_counter.setdefault(code_key, Counter())
            bucket[county_name] += 1
            air_code_rows += 1

            if progress_every_air > 0 and air_rows % progress_every_air == 0:
                print(
                    (
                        f"[progress][air] rows={air_rows:,} files_found={air_files_found} "
                        f"code_rows={air_code_rows:,} skipped_missing={air_skipped_missing:,} "
                        f"skipped_excluded_state={air_skipped_excluded_state:,}"
                    ),
                    file=sys.stderr,
                    flush=True,
                )

for (country_code, state_code, source_county_code), county_counter in code_name_counter.items():
    best_county_name, _ = county_counter.most_common(1)[0]
    if len(county_counter) > 1:
        air_name_conflicts += 1

    nk = county_nk(best_county_name, state_code, country_code)
    existing = county_members.get(nk)
    if existing is None:
        county_members[nk] = {
            "county_name": best_county_name,
            "state_code": state_code,
            "country_code": country_code,
            "source_county_code": source_county_code,
        }
    else:
        # Prefer code-backed county identity when available.
        if existing.get("source_county_code") is None:
            existing["source_county_code"] = source_county_code

if air_name_conflicts > 0:
    print("[top_air_code_name_conflicts]", file=sys.stderr, flush=True)
    conflict_items = [
        (key, counter)
        for key, counter in code_name_counter.items()
        if len(counter) > 1
    ]
    conflict_items.sort(key=lambda x: x[1].total(), reverse=True)
    for key, counter in conflict_items[:top_issues]:
        country_code, state_code, source_county_code = key
        parts = [f"{name}={count}" for name, count in counter.most_common(4)]
        print(
            f"  {country_code}|{state_code}|{source_county_code}: " + ", ".join(parts),
            file=sys.stderr,
            flush=True,
        )

rows_with_code = sum(1 for x in county_members.values() if x.get("source_county_code") is not None)

print(
    (
        f"[summary][accidents] rows={acc_rows:,} added={acc_added:,} "
        f"skipped_missing={acc_skipped_missing:,}"
    ),
    file=sys.stderr,
    flush=True,
)
print(
    (
        f"[summary][air] rows={air_rows:,} files_found={air_files_found} missing_files={air_missing_files} "
        f"code_rows={air_code_rows:,} skipped_missing={air_skipped_missing:,} "
        f"skipped_excluded_state={air_skipped_excluded_state:,} "
        f"code_name_conflicts={air_name_conflicts:,}"
    ),
    file=sys.stderr,
    flush=True,
)
print(
    f"[summary][counties] total={len(county_members):,} with_source_county_code={rows_with_code:,}",
    file=sys.stderr,
    flush=True,
)

for nk in sorted(county_members.keys()):
    row = county_members[nk]
    print(
        "\t".join(
            [
                tsv(nk),
                tsv(row["county_name"]),
                tsv(row["state_code"]),
                tsv(row["country_code"]),
                tsv(row["source_county_code"]),
            ]
        )
    )
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no v2 county rows extracted"
  exit 1
fi

# Stage + idempotent insert into dw.dim_county.
{
  cat <<'SQL'
CREATE TEMP TABLE stg_dim_county_v2 (
    county_nk          text PRIMARY KEY,
    county_name        text NOT NULL,
    state_code         text NOT NULL,
    country_code       text NOT NULL,
    source_county_code text
);
COPY stg_dim_county_v2 (
    county_nk,
    county_name,
    state_code,
    country_code,
    source_county_code
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t', NULL '\N');
SQL
  cat "${TMP_VALUES_FILE}"
  cat <<'SQL'
\.

INSERT INTO dw.dim_county (
    county_nk,
    county_name,
    state_code,
    country_code,
    source_county_code,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.county_nk,
    s.county_name,
    s.state_code,
    s.country_code,
    s.source_county_code,
    NOW() AS valid_from,
    TIMESTAMP '9999-12-31 23:59:59' AS valid_to,
    TRUE AS is_current
FROM stg_dim_county_v2 s
LEFT JOIN dw.dim_county d_nk
  ON d_nk.county_nk = s.county_nk
 AND d_nk.is_current = TRUE
LEFT JOIN dw.dim_county d_code
  ON s.source_county_code IS NOT NULL
 AND d_code.country_code = s.country_code
 AND d_code.state_code = s.state_code
 AND d_code.source_county_code = s.source_county_code
 AND d_code.is_current = TRUE
WHERE d_nk.county_key IS NULL
  AND d_code.county_key IS NULL;

DROP TABLE stg_dim_county_v2;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current v2 county cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c \"
    SELECT
      COUNT(*) AS dim_county_rows,
      COUNT(*) FILTER (WHERE is_current) AS current_rows,
      COUNT(*) FILTER (WHERE is_current AND source_county_code IS NOT NULL) AS current_rows_with_source_county_code
    FROM dw.dim_county;
  \""

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
