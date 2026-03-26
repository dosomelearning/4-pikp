# Project Agent Guide (Data Warehousing)

This project is focused on dimensional modeling and warehouse-style design.

## Scope
- Primary goal: design and document star schemas for selected US datasets.
- Database platform: PostgreSQL, used as a DW-style target (analytical modeling conventions apply).
- Current source focus: US-Accidents (Kaggle), with EPA AQS planned next.
- Infrastructure is containerized under `infra/` and operated via root `scripts/`.

## Modeling Defaults
- Prefer star schema (fact + denormalized dimensions).
- Fact grain must be explicitly documented before/with schema changes.
- Use surrogate keys for dimensions.
- Keep source natural keys where useful for lineage and SCD handling.
- Time dimension is static (non-SCD / Type 0), hour-level grain.
- Other selected dimensions default to SCD Type 2 unless explicitly changed.

## Current Baseline (US-Accidents)
- Dimension set: `time`, `location`, `weather_condition`, `road_condition`, `severity`.
- Fact table: `dw.fact_accident` keyed by source ID (`source_accident_id`) without fact surrogate key.
- Time dimension:
  - Smart surrogate `time_key` at hour grain (`YYYYMMDDHH`).
  - No minute/second granularity in `dim_time`.
  - Exact timestamps are preserved in fact (`start_time`, `end_time`).
- Severity dimension is intentionally minimal:
  - `severity_key`, `severity_level`, and SCD2 columns only.
- Quantitative weather metrics from source are currently excluded by design and documented in datasource markdown.

## SCD Type 2 Rules
- Keep versioning columns: `valid_from`, `valid_to`, `is_current`.
- Enforce one current row per business identifier (`*_nk`, or equivalent agreed identifier).
- When attribute changes:
  - close previous row (`valid_to`, `is_current = false`)
  - insert new row (`is_current = true`)

## Mapping and Documentation Rules
- Every modeled column must be classified in docs as:
  - `Original`
  - `Derived`
  - `Logistical`
- Keep source-to-star mappings in markdown tables and keep them in sync with SQL DDL.
- Record design decisions (and alternatives considered) in the datasource description docs.
- If fields are intentionally excluded, list them explicitly with rationale.

## Units and Data Semantics
- Keep original US units from source unless explicitly changed by user decision.
- Preserve original event timestamps in fact tables when time FKs are bucketed.

## SQL Conventions
- Use schema `dw`.
- In fact tables, keep dimension FKs grouped before measure columns.
- Add essential constraints and indexes for FK joins and basic data quality checks.
- Keep DDL explicit and readable; avoid unnecessary complexity.

## Infra and Scripts Conventions
- Compose layout is flat:
  - `infra/compose/compose.yml`
  - `infra/compose/.env` (local, not tracked)
  - `infra/compose/.env.example` (tracked)
- PostgreSQL init scripts live in `infra/platform/postgres/init/` with numeric prefixes.
- Use root scripts as the primary operational interface:
  - `./scripts/infra-up.sh`
  - `./scripts/infra-down.sh`
  - `./scripts/infra-logs.sh`
  - `./scripts/pg-smoketest.sh`
  - `./scripts/pg-psql.sh`
  - `./scripts/pg-apply-star-schema.sh`
  - `./scripts/pg-wipe-db.sh` (destructive: drops non-system schemas, resets to `public` + empty `dw`)

## Repository Data Handling
- Do not commit contents of `data/` and `raw/`; keep directories via `.gitkeep`.
- PostgreSQL persisted container data path is `data/pgdb`.
- Treat `infra/` as container/tooling area; avoid storing transient runtime artifacts in git.

## Collaboration Style
- Ask clarifying questions when modeling choices are ambiguous or materially impact schema.
- Prefer small, reversible edits and keep SQL and markdown aligned in the same change.

## Git Rules (Imported)
- Use read-only git commands (`git status`, `git diff`, `git log`, `git show`) regularly to navigate progress and validate assumptions.
- Prefer referring to concrete git diffs/history when summarizing what changed.
- Commit message style:
  - subject line in imperative mood
  - multi-line body with one bullet per logical change and blank lines between bullets
- User pushes to remote repositories exclusively.
- Agent may prepare commits and run other local git operations only with explicit user approval.
- Do not commit unless explicitly approved by the user.
- Read-only git commands are allowed; destructive/history-rewriting commands are not allowed unless explicitly requested.
- For task-tracked work, commit intent tags are mandatory:
  - `[checkpoint]` for partial/in-progress synchronization commits
  - `[close]` for task-closure commits
- For task-tracked work, all task-related commit messages must reference relevant `T-###` ID(s).
- For task-tracked work, a task may be set to `done` only on explicit user instruction.
- For task-tracked work, `[close]` commits are allowed only after explicit user instruction to set task status to `done`.

## Get Ready Convention
- In this project, the user command `get ready` means: read all files under `scripts/etl/` and all files under `docs/` before proceeding.
- This readiness list is expected to evolve; additional required paths may be added as we progress.
