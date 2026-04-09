#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/daily_aqi_by_county_2017.csv}"
RULES_JSON="${RULES_JSON:-${ROOT_DIR}/scripts/analysis/rules.json}"
PROGRESS_EVERY="${PROGRESS_EVERY:-5000}"
ROW_LIMIT="${ROW_LIMIT:-0}"
TOP_ISSUES="${TOP_ISSUES:-10}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  exit 1
fi

if [[ ! -f "${RAW_CSV}" ]]; then
  echo "ERROR: raw air-quality CSV not found: ${RAW_CSV}"
  exit 1
fi

if [[ ! -f "${RULES_JSON}" ]]; then
  echo "ERROR: rules file not found: ${RULES_JSON}"
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

echo "Loading dw.fact_air_quality_daily_v2 from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "rules_json: ${RULES_JSON}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"
if [[ "${ROW_LIMIT}" != "0" ]]; then
  echo "Row limit: ${ROW_LIMIT}"
fi
echo "Top issue samples: ${TOP_ISSUES}"

{
  # Stage table mirrors transformed source columns before FK key resolution.
  cat <<'SQL'
CREATE TEMP TABLE stg_fact_air_quality_daily_v2 (
    source_state_code          text,
    source_county_code         text,
    source_date                date,
    time_key                   integer,
    county_nk                  text,
    county_state_code          text,
    county_source_county_code  text,
    aqi_category_nk            text,
    defining_parameter_nk      text,
    aqi                        integer,
    number_of_sites_reporting  integer,
    defining_site_code         text
);
COPY stg_fact_air_quality_daily_v2 (
    source_state_code,
    source_county_code,
    source_date,
    time_key,
    county_nk,
    county_state_code,
    county_source_county_code,
    aqi_category_nk,
    defining_parameter_nk,
    aqi,
    number_of_sites_reporting,
    defining_site_code
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t', NULL '\N');
SQL

  python - "${RAW_CSV}" "${RULES_JSON}" "${PROGRESS_EVERY}" "${ROW_LIMIT}" "${TOP_ISSUES}" <<'PY'
import csv
import datetime
import json
import re
import sys
from collections import Counter

csv_path = sys.argv[1]
rules_json = sys.argv[2]
progress_every = int(sys.argv[3])
row_limit = int(sys.argv[4])
top_issues = int(sys.argv[5])

space_re = re.compile(r"\s+")
token_re = re.compile(r"[^a-z0-9]+")
underscore_re = re.compile(r"_+")


# Shared canonicalization and normalization helpers.
def canon(raw):
    if raw is None:
        return None
    cleaned = space_re.sub(" ", raw.strip())
    return cleaned if cleaned else None


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


def normalize_state_code(raw):
    value = canon(raw)
    if value is None:
        return None
    if value.isdigit() and len(value) <= 2:
        return value.zfill(2)
    return value


def normalize_county_code(raw):
    value = canon(raw)
    if value is None:
        return None
    if value.isdigit() and len(value) <= 3:
        return value.zfill(3)
    return value


def to_nk(text):
    nk = token_re.sub("_", text.lower())
    nk = underscore_re.sub("_", nk).strip("_")
    return nk


def get_field(row, candidates):
    for key in candidates:
        if key in row:
            return row.get(key)
    lowered = {k.lower(): v for k, v in row.items()}
    for key in candidates:
        v = lowered.get(key.lower())
        if v is not None:
            return v
    return None


def county_nk(county_name, state_code, country_code):
    return "C|" + "|".join([county_name, state_code, country_code])


def tsv(value):
    if value is None:
        return r"\N"
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


with open(rules_json, "r", encoding="utf-8") as f:
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

rows = 0
staged = 0
skipped = 0
skip_reason = {
    "missing_state_code": 0,
    "missing_county_code": 0,
    "missing_date": 0,
    "invalid_date": 0,
    "missing_county_name": 0,
    "missing_state_name": 0,
    "excluded_state_name_rule": 0,
    "unknown_state_name": 0,
    "invalid_aqi": 0,
    "invalid_sites_reporting": 0,
    "missing_category_mapped_unknown": 0,
    "missing_defining_parameter_mapped_unknown": 0,
}
excluded_state_counter = Counter()
unknown_state_counter = Counter()

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    # One-pass transform with explicit skip/mapping reasons for observability.
    for row in reader:
        rows += 1
        if row_limit > 0 and rows > row_limit:
            break

        source_state_code = normalize_state_code(row.get("State Code"))
        source_county_code = normalize_county_code(row.get("County Code"))
        if source_state_code is None:
            skipped += 1
            skip_reason["missing_state_code"] += 1
            continue
        if source_county_code is None:
            skipped += 1
            skip_reason["missing_county_code"] += 1
            continue

        date_raw = canon(row.get("Date"))
        if date_raw is None:
            skipped += 1
            skip_reason["missing_date"] += 1
            continue
        try:
            source_date = datetime.datetime.strptime(date_raw, "%Y-%m-%d").date()
        except ValueError:
            skipped += 1
            skip_reason["invalid_date"] += 1
            continue

        county_name = normalize_county_name(get_field(row, ["county Name", "County Name", "county_name"]))
        if county_name is None:
            skipped += 1
            skip_reason["missing_county_name"] += 1
            continue

        state_name = canon(get_field(row, ["State Name", "state_name"]))
        if state_name is None:
            skipped += 1
            skip_reason["missing_state_name"] += 1
            continue
        state_name_key = state_name.lower()
        if state_name_key in excluded_state_names:
            # Rule-driven out-of-scope rows (for example Country Of Mexico).
            skipped += 1
            skip_reason["excluded_state_name_rule"] += 1
            excluded_state_counter[state_name] += 1
            continue

        county_state_code = state_name_to_abbrev.get(state_name_key)
        if county_state_code is None:
            skipped += 1
            skip_reason["unknown_state_name"] += 1
            unknown_state_counter[state_name] += 1
            continue

        aqi_raw = canon(row.get("AQI"))
        sites_raw = canon(row.get("Number of Sites Reporting"))
        try:
            aqi = int(aqi_raw) if aqi_raw is not None else None
        except ValueError:
            aqi = None
        try:
            sites = int(sites_raw) if sites_raw is not None else None
        except ValueError:
            sites = None
        if aqi is None or aqi < 0:
            skipped += 1
            skip_reason["invalid_aqi"] += 1
            continue
        if sites is None or sites < 0:
            skipped += 1
            skip_reason["invalid_sites_reporting"] += 1
            continue

        category_name = canon(row.get("Category"))
        if category_name is None:
            # Keep mandatory FK loadable via explicit unknown member.
            category_nk = "unknown"
            skip_reason["missing_category_mapped_unknown"] += 1
        else:
            category_nk = to_nk(category_name)
            if category_nk == "":
                category_nk = "unknown"
                skip_reason["missing_category_mapped_unknown"] += 1

        param_name = canon(row.get("Defining Parameter"))
        if param_name is None:
            # Keep mandatory FK loadable via explicit unknown member.
            parameter_nk = "unknown"
            skip_reason["missing_defining_parameter_mapped_unknown"] += 1
        else:
            parameter_nk = to_nk(param_name)
            if parameter_nk == "":
                parameter_nk = "unknown"
                skip_reason["missing_defining_parameter_mapped_unknown"] += 1

        county_nk_value = county_nk(county_name, county_state_code, "US")
        time_key = int(f"{source_date.year:04d}{source_date.month:02d}{source_date.day:02d}00")
        defining_site_code = canon(row.get("Defining Site"))

        out = [
            source_state_code,
            source_county_code,
            source_date.isoformat(),
            time_key,
            county_nk_value,
            county_state_code,
            source_county_code,
            category_nk,
            parameter_nk,
            aqi,
            sites,
            defining_site_code,
        ]
        print("\t".join(tsv(v) for v in out))
        staged += 1

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} staged={staged:,} skipped={skipped:,}",
                file=sys.stderr,
                flush=True,
            )

print(
    f"[summary] rows_scanned={rows:,} staged={staged:,} skipped={skipped:,}",
    file=sys.stderr,
    flush=True,
)
for k in sorted(skip_reason.keys()):
    print(f"[skip_reason] {k}={skip_reason[k]:,}", file=sys.stderr, flush=True)
if excluded_state_counter:
    print("[top_excluded_state_names]", file=sys.stderr, flush=True)
    for name, count in excluded_state_counter.most_common(top_issues):
        print(f"  {count:>8}  {name}", file=sys.stderr, flush=True)
if unknown_state_counter:
    print("[top_unknown_state_names]", file=sys.stderr, flush=True)
    for name, count in unknown_state_counter.most_common(top_issues):
        print(f"  {count:>8}  {name}", file=sys.stderr, flush=True)
PY

  # Emit FK resolvability diagnostics before writing into fact table.
  cat <<'SQL'
\.

SELECT
  COUNT(*) AS staged_rows,
  COUNT(*) FILTER (WHERE dc.county_key IS NULL) AS unresolved_county_fk
FROM stg_fact_air_quality_daily_v2 s
LEFT JOIN dw.dim_county dc
  ON dc.is_current = TRUE
 AND dc.country_code = 'US'
 AND dc.state_code = s.county_state_code
 AND dc.source_county_code = s.county_source_county_code;

INSERT INTO dw.fact_air_quality_daily_v2 (
    source_state_code,
    source_county_code,
    source_date,
    time_key,
    county_key,
    aqi_category_key,
    defining_parameter_key,
    aqi,
    number_of_sites_reporting,
    defining_site_code
)
SELECT
    s.source_state_code,
    s.source_county_code,
    s.source_date,
    s.time_key,
    dc.county_key,
    ac.aqi_category_key,
    dp.defining_parameter_key,
    s.aqi,
    s.number_of_sites_reporting,
    s.defining_site_code
FROM stg_fact_air_quality_daily_v2 s
JOIN dw.dim_time dt
  ON dt.time_key = s.time_key
JOIN dw.dim_county dc
  ON dc.is_current = TRUE
 AND dc.country_code = 'US'
 AND dc.state_code = s.county_state_code
 AND dc.source_county_code = s.county_source_county_code
JOIN dw.dim_aqi_category ac
  ON ac.aqi_category_nk = s.aqi_category_nk
 AND ac.is_current = TRUE
JOIN dw.dim_defining_parameter dp
  ON dp.defining_parameter_nk = s.defining_parameter_nk
 AND dp.is_current = TRUE
ON CONFLICT (source_state_code, source_county_code, source_date) DO NOTHING;

DROP TABLE stg_fact_air_quality_daily_v2;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current v2 air fact cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT COUNT(*) AS fact_air_quality_daily_v2_rows FROM dw.fact_air_quality_daily_v2;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
