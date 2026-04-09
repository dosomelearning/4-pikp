#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/compose/compose.yml"
ENV_FILE="${ROOT_DIR}/infra/compose/.env"
RAW_CSV="${1:-${ROOT_DIR}/raw/archive/US_Accidents_March23.csv}"
PROGRESS_EVERY="${PROGRESS_EVERY:-250000}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}"
  exit 1
fi

if [[ ! -f "${RAW_CSV}" ]]; then
  echo "ERROR: raw accidents CSV not found: ${RAW_CSV}"
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

TMP_VALUES_FILE="$(mktemp)"
trap 'rm -f "${TMP_VALUES_FILE}"' EXIT

echo "Scanning road-condition combinations from: ${RAW_CSV}"
echo "started_at: ${RUN_START_HUMAN}"
echo "Progress interval: every ${PROGRESS_EVERY} rows"

python - "${RAW_CSV}" "${PROGRESS_EVERY}" <<'PY' > "${TMP_VALUES_FILE}"
import csv
import sys

csv_path = sys.argv[1]
progress_every = int(sys.argv[2])

source_flags = [
    ("Amenity", "amenity"),
    ("Bump", "bump"),
    ("Crossing", "crossing"),
    ("Give_Way", "give_way"),
    ("Junction", "junction"),
    ("No_Exit", "no_exit"),
    ("Railway", "railway"),
    ("Roundabout", "roundabout"),
    ("Station", "station"),
    ("Stop", "stop_sign"),
    ("Traffic_Calming", "traffic_calming"),
    ("Traffic_Signal", "traffic_signal"),
    ("Turning_Loop", "turning_loop"),
]

true_values = {"1", "true", "t", "yes", "y"}

def as_bool(raw: str) -> bool:
    if raw is None:
        return False
    s = raw.strip().lower()
    if s == "":
        return False
    return s in true_values

combos = {}
rows = 0

with open(csv_path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows += 1
        bits = tuple(as_bool(row.get(src)) for src, _ in source_flags)
        combos[bits] = combos.get(bits, 0) + 1

        if progress_every > 0 and rows % progress_every == 0:
            print(
                f"[progress] rows={rows:,} distinct_combinations={len(combos):,}",
                file=sys.stderr,
                flush=True,
            )

print(
    f"[summary] rows={rows:,} distinct_combinations={len(combos):,}",
    file=sys.stderr,
    flush=True,
)

# Output TSV for COPY:
# road_condition_nk + 13 booleans (true/false)
for bits in sorted(combos.keys()):
    nk = "|".join("1" if b else "0" for b in bits)
    bool_text = ["true" if b else "false" for b in bits]
    print("\t".join([nk] + bool_text))
PY

if [[ ! -s "${TMP_VALUES_FILE}" ]]; then
  echo "ERROR: no road-condition combinations extracted from ${RAW_CSV}"
  exit 1
fi

{
  cat <<'SQL'
CREATE TEMP TABLE stg_road_condition (
    road_condition_nk text PRIMARY KEY,
    amenity boolean NOT NULL,
    bump boolean NOT NULL,
    crossing boolean NOT NULL,
    give_way boolean NOT NULL,
    junction boolean NOT NULL,
    no_exit boolean NOT NULL,
    railway boolean NOT NULL,
    roundabout boolean NOT NULL,
    station boolean NOT NULL,
    stop_sign boolean NOT NULL,
    traffic_calming boolean NOT NULL,
    traffic_signal boolean NOT NULL,
    turning_loop boolean NOT NULL
);
COPY stg_road_condition (
    road_condition_nk,
    amenity,
    bump,
    crossing,
    give_way,
    junction,
    no_exit,
    railway,
    roundabout,
    station,
    stop_sign,
    traffic_calming,
    traffic_signal,
    turning_loop
) FROM STDIN WITH (FORMAT text, DELIMITER E'\t');
SQL
  cat "${TMP_VALUES_FILE}"
  cat <<'SQL'
\.

INSERT INTO dw.dim_road_condition (
    road_condition_nk,
    amenity,
    bump,
    crossing,
    give_way,
    junction,
    no_exit,
    railway,
    roundabout,
    station,
    stop_sign,
    traffic_calming,
    traffic_signal,
    turning_loop,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.road_condition_nk,
    s.amenity,
    s.bump,
    s.crossing,
    s.give_way,
    s.junction,
    s.no_exit,
    s.railway,
    s.roundabout,
    s.station,
    s.stop_sign,
    s.traffic_calming,
    s.traffic_signal,
    s.turning_loop,
    NOW() AS valid_from,
    TIMESTAMP '9999-12-31 23:59:59' AS valid_to,
    TRUE AS is_current
FROM stg_road_condition s
LEFT JOIN dw.dim_road_condition d
  ON d.road_condition_nk = s.road_condition_nk
 AND d.is_current = TRUE
WHERE d.road_condition_nk IS NULL;

DROP TABLE stg_road_condition;
SQL
} | docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -v ON_ERROR_STOP=1"

echo "Done. Current road-condition cardinality:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres \
  bash -lc "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' -c 'SELECT COUNT(*) AS dim_road_condition_rows, COUNT(*) FILTER (WHERE is_current) AS current_rows FROM dw.dim_road_condition;'"

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
