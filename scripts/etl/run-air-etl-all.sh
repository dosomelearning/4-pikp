#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/docs/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RAW_CORRELATION_ID="${CORRELATION_ID:-}"
CORRELATION_ID=""
if [[ -n "${RAW_CORRELATION_ID}" ]]; then
  CORRELATION_ID="$(printf '%s' "${RAW_CORRELATION_ID}" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9')"
  if [[ -z "${CORRELATION_ID}" ]]; then
    echo "ERROR: CORRELATION_ID provided but empty after normalization"
    exit 1
  fi
fi
LOG_PREFIX=""
if [[ -n "${CORRELATION_ID}" ]]; then
  LOG_PREFIX="${CORRELATION_ID}_"
fi
LOG_FILE="${LOG_DIR}/${LOG_PREFIX}air_etl_all_${TIMESTAMP}.log"

AIR_DIR="${AIR_DIR:-${ROOT_DIR}/raw}"
AIR_START_YEAR="${AIR_START_YEAR:-2016}"
AIR_END_YEAR="${AIR_END_YEAR:-2023}"
PROGRESS_EVERY="${PROGRESS_EVERY:-5000}"
ROW_LIMIT="${ROW_LIMIT:-0}"
RUN_FACT="${RUN_FACT:-1}"
TOP_ISSUES="${TOP_ISSUES:-10}"
MISSING_FILE_MODE="${MISSING_FILE_MODE:-warn}"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

RUN_START_EPOCH="$(date +%s)"
RUN_START_HUMAN="$(date -Iseconds)"

if [[ "${AIR_START_YEAR}" -gt "${AIR_END_YEAR}" ]]; then
  echo "ERROR: AIR_START_YEAR must be <= AIR_END_YEAR"
  echo "  AIR_START_YEAR=${AIR_START_YEAR}"
  echo "  AIR_END_YEAR=${AIR_END_YEAR}"
  exit 1
fi

echo "Air-quality ETL all-years runner"
echo "started_at: ${RUN_START_HUMAN}"
echo "log_file: ${LOG_FILE}"
echo "correlation_id: ${CORRELATION_ID:-<none>}"
echo "air_dir: ${AIR_DIR}"
echo "year_range: ${AIR_START_YEAR}-${AIR_END_YEAR}"
echo "run_fact: ${RUN_FACT}"
echo "progress_every: ${PROGRESS_EVERY}"
echo "row_limit_fact: ${ROW_LIMIT}"
echo "top_issues: ${TOP_ISSUES}"
echo "missing_file_mode: ${MISSING_FILE_MODE}"

processed_years=0
missing_years=0
failed_years=0

for year in $(seq "${AIR_START_YEAR}" "${AIR_END_YEAR}"); do
  csv_file="${AIR_DIR}/daily_aqi_by_county_${year}.csv"
  if [[ ! -f "${csv_file}" ]]; then
    missing_years=$((missing_years + 1))
    echo
    echo "=== Year ${year} ==="
    echo "status: missing_file (${csv_file})"
    if [[ "${MISSING_FILE_MODE}" == "error" ]]; then
      echo "ERROR: required file missing and MISSING_FILE_MODE=error"
      exit 1
    fi
    continue
  fi

  processed_years=$((processed_years + 1))
  echo
  echo "=== Year ${year} ==="
  echo "csv_file: ${csv_file}"
  echo "started_at: $(date -Iseconds)"
  if ! env \
      CORRELATION_ID="${CORRELATION_ID}" \
      PROGRESS_EVERY="${PROGRESS_EVERY}" \
      ROW_LIMIT="${ROW_LIMIT}" \
      RUN_FACT="${RUN_FACT}" \
      TOP_ISSUES="${TOP_ISSUES}" \
      RAW_CSV="${csv_file}" \
      "${ROOT_DIR}/scripts/etl/run-air-etl.sh" \
      "${csv_file}"; then
    failed_years=$((failed_years + 1))
    echo "status: failed"
    if [[ "${MISSING_FILE_MODE}" == "error" ]]; then
      echo "ERROR: stopping due to year failure and MISSING_FILE_MODE=error"
      exit 1
    fi
    continue
  fi
  echo "status: ok"
done

RUN_END_EPOCH="$(date +%s)"
RUN_END_HUMAN="$(date -Iseconds)"

echo
echo "Air-quality ETL all-years runner completed"
echo "finished_at: ${RUN_END_HUMAN}"
echo "total_runtime_seconds: $((RUN_END_EPOCH - RUN_START_EPOCH))"
echo "processed_years: ${processed_years}"
echo "missing_years: ${missing_years}"
echo "failed_years: ${failed_years}"
echo "log_file: ${LOG_FILE}"
