# Analysis Scripts Usage

Operational usage for manual raw-analysis runs.

All commands below assume you are in project root:
- `/home/raven/data/doc/privat/uni/univaje/4-pikp`

## 1) Run All Analysis (Accidents + Air)

This runs data-shape first, then accidents, then air.

Default:

```bash
./scripts/analysis/run-analysis-all.sh
```

With overrides:

```bash
ACCIDENTS_RAW=./raw/archive/US_Accidents_March23.csv \
RAW_DIR=./raw \
AIR_START_YEAR=2016 \
AIR_END_YEAR=2023 \
ACCIDENTS_PROGRESS_EVERY=250000 \
AIR_PROGRESS_EVERY=50000 \
TOP_ISSUES=10 \
./scripts/analysis/run-analysis-all.sh
```

## 2) Run Accidents Analysis Only

This runs data-shape first by default.

Default input:

```bash
./scripts/analysis/run-accidents-analysis.sh
```

Custom accidents file + logging controls:

```bash
PROGRESS_EVERY=250000 \
TOP_ISSUES=10 \
./scripts/analysis/run-accidents-analysis.sh ./raw/archive/US_Accidents_March23.csv
```

Skip automatic data-shape step:

```bash
SKIP_DATA_SHAPE=1 ./scripts/analysis/run-accidents-analysis.sh
```

## 3) Run Air Analysis Only (Year Range)

This runs data-shape first by default.

Default:

```bash
./scripts/analysis/run-air-analysis-all.sh
```

Custom range + logging controls:

```bash
RAW_DIR=./raw \
AIR_START_YEAR=2016 \
AIR_END_YEAR=2023 \
PROGRESS_EVERY=50000 \
TOP_ISSUES=10 \
./scripts/analysis/run-air-analysis-all.sh
```

Skip automatic data-shape step:

```bash
SKIP_DATA_SHAPE=1 ./scripts/analysis/run-air-analysis-all.sh
```

## 4) Run Data-Shape Analysis Only

Default:

```bash
./scripts/analysis/run-data-shape-analysis.sh
```

Custom paths/range:

```bash
ACCIDENTS_RAW=./raw/archive/US_Accidents_March23.csv \
RAW_DIR=./raw \
AIR_START_YEAR=2016 \
AIR_END_YEAR=2023 \
./scripts/analysis/run-data-shape-analysis.sh
```

## Output Targets

- Main metrics artifact:
  - `docs/analysis.json`
- Run-all logs:
  - `docs/logs/analysis_all_YYYYMMDD_HHMMSS.log`

## Notes

- Scripts are non-interactive; they emit periodic progress and final summaries to console.
- Yearly air files are expected as:
  - `raw/daily_aqi_by_county_YYYY.csv`

## Reset Analysis JSON (Clear to Placeholders)

Reset all computed/discovered values in `docs/analysis.json` while keeping schema shape.

Default:

```bash
./scripts/analysis/analysis_json_clear.sh
```

Custom target path:

```bash
ANALYSIS_JSON=./docs/analysis.json ./scripts/analysis/analysis_json_clear.sh
```
