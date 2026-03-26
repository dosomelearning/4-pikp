#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path


SPACE_RE = re.compile(r"\s+")
TOKEN_RE = re.compile(r"[^a-z0-9]+")
UNDERSCORE_RE = re.compile(r"_+")
TS_HEAD_RE = re.compile(r"^(\d{4}[-/]\d{2}[-/]\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d+))?")
TRUE_VALUES = {"1", "true", "t", "yes", "y"}

ROAD_FLAG_COLS = [
    "Amenity",
    "Bump",
    "Crossing",
    "Give_Way",
    "Junction",
    "No_Exit",
    "Railway",
    "Roundabout",
    "Station",
    "Stop",
    "Traffic_Calming",
    "Traffic_Signal",
    "Turning_Loop",
]

STATE_NAME_TO_ABBREV = {
    "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
    "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
    "district of columbia": "DC", "florida": "FL", "georgia": "GA", "hawaii": "HI",
    "idaho": "ID", "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
    "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
    "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
    "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
    "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
    "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
    "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI",
    "south carolina": "SC", "south dakota": "SD", "tennessee": "TN", "texas": "TX",
    "utah": "UT", "vermont": "VT", "virginia": "VA", "washington": "WA",
    "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
    "puerto rico": "PR", "guam": "GU", "american samoa": "AS",
    "virgin islands": "VI", "northern mariana islands": "MP",
}


def canon(raw):
    if raw is None:
        return None
    cleaned = SPACE_RE.sub(" ", raw.strip())
    return cleaned if cleaned else None


def to_nk(text):
    nk = TOKEN_RE.sub("_", text.lower())
    nk = UNDERSCORE_RE.sub("_", nk).strip("_")
    return nk


def as_bool(raw):
    if raw is None:
        return False
    s = raw.strip().lower()
    if s == "":
        return False
    return s in TRUE_VALUES


def as_float(raw):
    if raw is None:
        return None
    s = raw.strip()
    if s == "":
        return None
    return float(s)


def parse_ts(raw):
    if raw is None:
        return None
    s = raw.strip()
    if s == "":
        return None
    m = TS_HEAD_RE.match(s)
    if m:
        base = m.group(1).replace("/", "-")
        frac = m.group(2)
        if frac:
            s = f"{base}.{(frac[:6]).ljust(6, '0')}"
        else:
            s = base
    else:
        s = s.replace("/", "-")
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return dt.datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


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


def format_top(counter, top_n):
    out = []
    for name, count in counter.most_common(top_n):
        out.append({"name": name, "count": count})
    return out


def ensure_analysis_skeleton(path):
    if path.exists():
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    raise FileNotFoundError(f"analysis json not found: {path}")


def write_analysis(path, data):
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")


def analyze_accidents(raw_csv, progress_every, top_issues):
    rows = 0

    time_keys = set()
    min_ts = None
    max_ts = None
    severity_levels = set()
    weather_nk = set()
    missing_weather_rows = 0
    road_combos = set()
    detail_nk = set()
    county_nk = set()
    insufficient_location_rows = 0

    source_ids = Counter()

    expected_stage_rows = 0
    expected_unknown_mapped_rows = 0
    skip_reason = {
        "missing_id": 0,
        "severity": 0,
        "time_parse": 0,
        "time_order": 0,
        "coords": 0,
        "location_detail": 0,
        "location_county": 0,
    }

    with open(raw_csv, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows += 1
            if progress_every > 0 and rows % progress_every == 0:
                print(f"[progress][accidents] rows={rows:,}", file=sys.stderr, flush=True)

            source_id = canon(row.get("ID"))
            if source_id is not None:
                source_ids[source_id] += 1

            start_dt = parse_ts(row.get("Start_Time"))
            end_dt = parse_ts(row.get("End_Time"))
            for t in (start_dt, end_dt):
                if t is not None:
                    time_keys.add(int(f"{t.year:04d}{t.month:02d}{t.day:02d}{t.hour:02d}"))
                    min_ts = t if min_ts is None or t < min_ts else min_ts
                    max_ts = t if max_ts is None or t > max_ts else max_ts

            sev_raw = canon(row.get("Severity"))
            try:
                sev = int(sev_raw) if sev_raw is not None else None
            except ValueError:
                sev = None
            if sev is not None and sev > 0:
                severity_levels.add(sev)

            weather_raw = canon(row.get("Weather_Condition"))
            if weather_raw is None:
                missing_weather_rows += 1
            else:
                weather_nk.add(weather_raw.lower())

            road_bits = ["1" if as_bool(row.get(col)) else "0" for col in ROAD_FLAG_COLS]
            road_combos.add("|".join(road_bits))

            street = canon(row.get("Street"))
            city = canon(row.get("City"))
            county = canon(row.get("County"))
            state = canon(row.get("State"))
            zipcode = canon(row.get("Zipcode"))
            country = canon(row.get("Country"))
            timezone = canon(row.get("Timezone"))

            if any(v is not None for v in (street, city, county, state, zipcode, country, timezone)):
                detail_nk.add("D|" + "|".join([
                    street or "", city or "", county or "", state or "", zipcode or "", country or "", timezone or ""
                ]))
            else:
                insufficient_location_rows += 1

            if any(v is not None for v in (county, state, country)):
                county_nk.add("C|" + "|".join([county or "", state or "", country or ""]))

            # Fact-level checks (same logic as ETL)
            if source_id is None:
                skip_reason["missing_id"] += 1
                continue

            if sev is None or sev <= 0:
                skip_reason["severity"] += 1
                continue

            if start_dt is None or end_dt is None:
                skip_reason["time_parse"] += 1
                continue

            if end_dt < start_dt:
                skip_reason["time_order"] += 1
                continue

            try:
                start_lat = as_float(row.get("Start_Lat"))
                start_lng = as_float(row.get("Start_Lng"))
                end_lat = as_float(row.get("End_Lat"))
                end_lng = as_float(row.get("End_Lng"))
            except ValueError:
                skip_reason["coords"] += 1
                continue

            if start_lat is None or start_lng is None:
                skip_reason["coords"] += 1
                continue
            if not (-90 <= start_lat <= 90 and -180 <= start_lng <= 180):
                skip_reason["coords"] += 1
                continue
            if end_lat is not None and not (-90 <= end_lat <= 90):
                end_lat = None
            if end_lng is not None and not (-180 <= end_lng <= 180):
                end_lng = None

            if not any(v is not None for v in (street, city, county, state, zipcode, country, timezone)):
                skip_reason["location_detail"] += 1
                continue

            if not any(v is not None for v in (county, state, country)):
                skip_reason["location_county"] += 1
                continue

            expected_stage_rows += 1
            if weather_raw is None:
                expected_unknown_mapped_rows += 1

    duplicate_source_id_rows = sum(c - 1 for c in source_ids.values() if c > 1)
    expected_skip_rows = sum(skip_reason.values())

    def ts_or_none(t):
        return t.strftime("%Y-%m-%d %H:%M:%S") if t else None

    metrics = {
        "dimensions": {
            "input_rows_total": rows,
            "dim_time": {
                "min_timestamp": ts_or_none(min_ts),
                "max_timestamp": ts_or_none(max_ts),
                "distinct_time_keys_expected": len(time_keys),
            },
            "dim_severity": {
                "distinct_valid_levels_expected": len(severity_levels),
                "levels": sorted(severity_levels),
            },
            "dim_weather_condition": {
                "distinct_categories_expected": len(weather_nk),
                "missing_weather_rows": missing_weather_rows,
            },
            "dim_road_condition": {
                "distinct_combinations_expected": len(road_combos),
            },
            "dim_location": {
                "detail_members_expected": len(detail_nk),
                "county_members_expected": len(county_nk),
                "insufficient_location_rows": insufficient_location_rows,
            },
        },
        "facts": {
            "source_rows_total": rows,
            "source_id_duplicate_rows": duplicate_source_id_rows,
            "expected_stage_rows": expected_stage_rows,
            "expected_skip_rows": expected_skip_rows,
            "expected_unknown_mapped_rows": expected_unknown_mapped_rows,
            "skip_reasons": skip_reason,
        },
    }

    print(
        f"[summary][accidents] rows={rows:,} stage={expected_stage_rows:,} "
        f"skip={expected_skip_rows:,} dup_source_id_rows={duplicate_source_id_rows:,}",
        file=sys.stderr,
        flush=True,
    )
    return metrics


def analyze_air_file(raw_csv, progress_every, top_issues):
    rows = 0
    min_date = None
    max_date = None

    county_nk = set()
    aqi_nk = set()
    param_nk = set()
    unknown_state_counter = Counter()

    stage_rows = 0
    skip_reason = {
        "missing_state_code": 0,
        "missing_county_code": 0,
        "missing_date": 0,
        "invalid_date": 0,
        "missing_county_name": 0,
        "unknown_state_name": 0,
        "invalid_aqi": 0,
        "invalid_sites_reporting": 0,
        "missing_category_mapped_unknown": 0,
        "missing_defining_parameter_mapped_unknown": 0,
    }

    grain_counter = Counter()

    with open(raw_csv, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows += 1
            if progress_every > 0 and rows % progress_every == 0:
                print(f"[progress][air] file={raw_csv} rows={rows:,}", file=sys.stderr, flush=True)

            state_code = canon(row.get("State Code"))
            county_code = canon(row.get("County Code"))

            date_raw = canon(row.get("Date"))
            parsed_date = None
            if date_raw is not None:
                try:
                    parsed_date = dt.datetime.strptime(date_raw, "%Y-%m-%d").date()
                    min_date = parsed_date if min_date is None or parsed_date < min_date else min_date
                    max_date = parsed_date if max_date is None or parsed_date > max_date else max_date
                except ValueError:
                    pass

            category_name = canon(row.get("Category"))
            if category_name is not None:
                nk = to_nk(category_name)
                if nk:
                    aqi_nk.add(nk)

            param_name = canon(row.get("Defining Parameter"))
            if param_name is not None:
                nk = to_nk(param_name)
                if nk:
                    param_nk.add(nk)

            county_name = canon(get_field(row, ["county Name", "County Name", "county_name"]))
            state_name = canon(get_field(row, ["State Name", "state_name"]))
            state_abbrev = STATE_NAME_TO_ABBREV.get(state_name.lower()) if state_name else None
            if county_name is not None and state_abbrev is not None:
                county_nk.add("C|" + "|".join([county_name, state_abbrev, "US"]))
            elif state_abbrev is None:
                unknown_state_counter[state_name or "<NULL>"] += 1

            # Fact-logic checks
            if state_code is None:
                skip_reason["missing_state_code"] += 1
                continue
            if county_code is None:
                skip_reason["missing_county_code"] += 1
                continue
            if date_raw is None:
                skip_reason["missing_date"] += 1
                continue
            try:
                source_date = dt.datetime.strptime(date_raw, "%Y-%m-%d").date()
            except ValueError:
                skip_reason["invalid_date"] += 1
                continue
            if county_name is None:
                skip_reason["missing_county_name"] += 1
                continue
            if state_abbrev is None:
                skip_reason["unknown_state_name"] += 1
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
                skip_reason["invalid_aqi"] += 1
                continue
            if sites is None or sites < 0:
                skip_reason["invalid_sites_reporting"] += 1
                continue

            if category_name is None or to_nk(category_name) == "":
                skip_reason["missing_category_mapped_unknown"] += 1
            if param_name is None or to_nk(param_name) == "":
                skip_reason["missing_defining_parameter_mapped_unknown"] += 1

            stage_rows += 1
            grain_counter[(state_code, county_code, source_date.isoformat())] += 1

    duplicate_grain_rows = sum(c - 1 for c in grain_counter.values() if c > 1)
    skip_rows = (
        skip_reason["missing_state_code"]
        + skip_reason["missing_county_code"]
        + skip_reason["missing_date"]
        + skip_reason["invalid_date"]
        + skip_reason["missing_county_name"]
        + skip_reason["unknown_state_name"]
        + skip_reason["invalid_aqi"]
        + skip_reason["invalid_sites_reporting"]
    )

    year = Path(raw_csv).stem.rsplit("_", 1)[-1]
    metrics = {
        "rows_total": rows,
        "min_source_date": min_date.isoformat() if min_date else None,
        "max_source_date": max_date.isoformat() if max_date else None,
        "county_nk_expected_distinct": len(county_nk),
        "aqi_category_nk_expected_distinct": len(aqi_nk),
        "defining_parameter_nk_expected_distinct": len(param_nk),
        "unknown_state_name_rows": sum(unknown_state_counter.values()),
        "top_unknown_state_names": format_top(unknown_state_counter, top_issues),
        "facts": {
            "rows_scanned": rows,
            "expected_stage_rows": stage_rows,
            "expected_skip_rows": skip_rows,
            "duplicate_source_grain_rows": duplicate_grain_rows,
            "skip_reasons": skip_reason,
        },
    }

    print(
        f"[summary][air][{year}] rows={rows:,} stage={stage_rows:,} skip={skip_rows:,} "
        f"dup_grain_rows={duplicate_grain_rows:,}",
        file=sys.stderr,
        flush=True,
    )
    return metrics


def aggregate_air(per_year):
    all_county = 0
    all_aqi = 0
    all_param = 0
    all_rows = 0
    all_stage = 0
    all_skip = 0
    min_date = None
    max_date = None
    top_unknown = Counter()
    skip_reasons_total = defaultdict(int)

    for metrics in per_year.values():
        all_rows += metrics["rows_total"]
        all_stage += metrics["facts"]["expected_stage_rows"]
        all_skip += metrics["facts"]["expected_skip_rows"]
        all_county += 0
        all_aqi += 0
        all_param += 0

        d1 = metrics.get("min_source_date")
        d2 = metrics.get("max_source_date")
        if d1 is not None:
            min_date = d1 if min_date is None or d1 < min_date else min_date
        if d2 is not None:
            max_date = d2 if max_date is None or d2 > max_date else max_date

        for item in metrics.get("top_unknown_state_names", []):
            top_unknown[item["name"]] += item["count"]
        for k, v in metrics["facts"]["skip_reasons"].items():
            skip_reasons_total[k] += v

    # Distinct counts are not additive across years; compute separately from per-year placeholders:
    # caller injects the cross-year distincts.
    return {
        "rows_total": all_rows,
        "expected_stage_rows_total": all_stage,
        "expected_skip_rows_total": all_skip,
        "expected_min_source_date": min_date,
        "expected_max_source_date": max_date,
        "skip_reasons_total": dict(skip_reasons_total),
        "top_unknown_state_names": format_top(top_unknown, 10),
        "county_nk_expected_distinct": None,
        "aqi_category_nk_expected_distinct": None,
        "defining_parameter_nk_expected_distinct": None,
        "unknown_state_name_rows": skip_reasons_total.get("unknown_state_name", 0),
    }


def analyze_air_all(raw_dir, start_year, end_year, progress_every, top_issues):
    per_year = {}
    files_detected = []

    all_county = set()
    all_aqi = set()
    all_param = set()

    for year in range(start_year, end_year + 1):
        csv_path = Path(raw_dir) / f"daily_aqi_by_county_{year}.csv"
        if not csv_path.exists():
            continue
        files_detected.append(str(csv_path))
        y = str(year)
        m = analyze_air_file(str(csv_path), progress_every, top_issues)
        per_year[y] = m

        # recompute sets for global distinct counts from yearly metrics by rescanning lightweight values
        # (we need exact union, not sum); using single pass file here for correctness.
        with csv_path.open(newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                county_name = canon(get_field(row, ["county Name", "County Name", "county_name"]))
                state_name = canon(get_field(row, ["State Name", "state_name"]))
                state_abbrev = STATE_NAME_TO_ABBREV.get(state_name.lower()) if state_name else None
                if county_name is not None and state_abbrev is not None:
                    all_county.add("C|" + "|".join([county_name, state_abbrev, "US"]))

                category_name = canon(row.get("Category"))
                if category_name is not None:
                    nk = to_nk(category_name)
                    if nk:
                        all_aqi.add(nk)

                param_name = canon(row.get("Defining Parameter"))
                if param_name is not None:
                    nk = to_nk(param_name)
                    if nk:
                        all_param.add(nk)

    agg = aggregate_air(per_year)
    agg["county_nk_expected_distinct"] = len(all_county)
    agg["aqi_category_nk_expected_distinct"] = len(all_aqi)
    agg["defining_parameter_nk_expected_distinct"] = len(all_param)

    return {"files_detected": files_detected, "per_year": per_year, "all_years": agg}


def run_sql(sql):
    root = Path(__file__).resolve().parents[2]
    env_file = root / "infra/compose/.env"
    compose_file = root / "infra/compose/compose.yml"
    cmd = (
        f"set -a && source '{env_file}' && set +a && "
        f"docker compose --env-file '{env_file}' -f '{compose_file}' exec -T postgres "
        f"bash -lc \"PGPASSWORD='${{POSTGRES_PASSWORD}}' psql -U '${{POSTGRES_USER}}' -d '${{POSTGRES_DB}}' "
        f"-v ON_ERROR_STOP=1 -At -F $'\\t' -c \\\"{sql}\\\"\""
    )
    out = subprocess.check_output(["bash", "-c", cmd], text=True)
    return [line.strip().split("\t") for line in out.strip().splitlines() if line.strip()]


def validate_against_db(analysis):
    results = {"checks": []}

    # accidents fact count
    db_acc_rows = int(run_sql("SELECT COUNT(*) FROM dw.fact_accident;")[0][0])
    exp_acc_rows = analysis["accidents"]["facts"]["expected_stage_rows"]
    results["checks"].append({
        "name": "accidents.fact_rows",
        "expected": exp_acc_rows,
        "actual": db_acc_rows,
        "status": "pass" if exp_acc_rows == db_acc_rows else "fail",
    })

    # air fact count + range
    db_air = run_sql(
        "SELECT COUNT(*), MIN(source_date)::text, MAX(source_date)::text FROM dw.fact_air_quality_daily;"
    )[0]
    db_air_rows = int(db_air[0])
    db_air_min = db_air[1]
    db_air_max = db_air[2]
    exp_air_rows = analysis["air"]["facts"]["all_years"]["expected_stage_rows_total"]
    exp_air_min = analysis["air"]["facts"]["all_years"]["expected_min_source_date"]
    exp_air_max = analysis["air"]["facts"]["all_years"]["expected_max_source_date"]
    results["checks"].append({
        "name": "air.fact_rows",
        "expected": exp_air_rows,
        "actual": db_air_rows,
        "status": "pass" if exp_air_rows == db_air_rows else "fail",
    })
    results["checks"].append({
        "name": "air.fact_min_source_date",
        "expected": exp_air_min,
        "actual": db_air_min,
        "status": "pass" if exp_air_min == db_air_min else "fail",
    })
    results["checks"].append({
        "name": "air.fact_max_source_date",
        "expected": exp_air_max,
        "actual": db_air_max,
        "status": "pass" if exp_air_max == db_air_max else "fail",
    })

    # dimension current counts for new air dims
    db_aqi_dim = int(run_sql("SELECT COUNT(*) FROM dw.dim_aqi_category WHERE is_current=TRUE;")[0][0])
    db_param_dim = int(run_sql("SELECT COUNT(*) FROM dw.dim_defining_parameter WHERE is_current=TRUE;")[0][0])
    exp_aqi_dim = analysis["air"]["dimensions"]["all_years"]["aqi_category_nk_expected_distinct"] + 1
    exp_param_dim = analysis["air"]["dimensions"]["all_years"]["defining_parameter_nk_expected_distinct"] + 1
    results["checks"].append({
        "name": "air.dim_aqi_category_current_rows",
        "expected": exp_aqi_dim,
        "actual": db_aqi_dim,
        "status": "pass" if exp_aqi_dim == db_aqi_dim else "fail",
    })
    results["checks"].append({
        "name": "air.dim_defining_parameter_current_rows",
        "expected": exp_param_dim,
        "actual": db_param_dim,
        "status": "pass" if exp_param_dim == db_param_dim else "fail",
    })

    fail_count = sum(1 for c in results["checks"] if c["status"] == "fail")
    results["summary"] = {
        "total_checks": len(results["checks"]),
        "failed_checks": fail_count,
        "status": "pass" if fail_count == 0 else "fail",
    }
    return results


def cmd_analyze_accidents(args):
    analysis_path = Path(args.analysis_json)
    data = ensure_analysis_skeleton(analysis_path)
    data["accidents"] = analyze_accidents(args.raw_csv, args.progress_every, args.top_issues)
    write_analysis(analysis_path, data)


def cmd_analyze_air(args):
    analysis_path = Path(args.analysis_json)
    data = ensure_analysis_skeleton(analysis_path)
    air = analyze_air_all(args.raw_dir, args.start_year, args.end_year, args.progress_every, args.top_issues)
    data["air"]["dimensions"]["files_detected"] = air["files_detected"]
    data["air"]["dimensions"]["per_year"] = {}
    data["air"]["facts"]["per_year"] = {}
    for year, m in air["per_year"].items():
        data["air"]["dimensions"]["per_year"][year] = {
            "rows_total": m["rows_total"],
            "min_source_date": m["min_source_date"],
            "max_source_date": m["max_source_date"],
            "county_nk_expected_distinct": m["county_nk_expected_distinct"],
            "aqi_category_nk_expected_distinct": m["aqi_category_nk_expected_distinct"],
            "defining_parameter_nk_expected_distinct": m["defining_parameter_nk_expected_distinct"],
            "unknown_state_name_rows": m["unknown_state_name_rows"],
            "top_unknown_state_names": m["top_unknown_state_names"],
        }
        data["air"]["facts"]["per_year"][year] = m["facts"]

    data["air"]["dimensions"]["all_years"] = {
        "rows_total": air["all_years"]["rows_total"],
        "county_nk_expected_distinct": air["all_years"]["county_nk_expected_distinct"],
        "aqi_category_nk_expected_distinct": air["all_years"]["aqi_category_nk_expected_distinct"],
        "defining_parameter_nk_expected_distinct": air["all_years"]["defining_parameter_nk_expected_distinct"],
        "unknown_state_name_rows": air["all_years"]["unknown_state_name_rows"],
        "top_unknown_state_names": air["all_years"]["top_unknown_state_names"],
    }
    data["air"]["facts"]["all_years"] = {
        "rows_scanned_total": air["all_years"]["rows_total"],
        "expected_stage_rows_total": air["all_years"]["expected_stage_rows_total"],
        "expected_skip_rows_total": air["all_years"]["expected_skip_rows_total"],
        "expected_min_source_date": air["all_years"]["expected_min_source_date"],
        "expected_max_source_date": air["all_years"]["expected_max_source_date"],
        "skip_reasons_total": air["all_years"]["skip_reasons_total"],
    }
    write_analysis(analysis_path, data)


def cmd_validate(args):
    analysis_path = Path(args.analysis_json)
    data = ensure_analysis_skeleton(analysis_path)
    report = validate_against_db(data)
    out_path = Path(args.output_json)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"[validation] report={out_path}")
    for check in report["checks"]:
        print(
            f"[check] {check['name']} status={check['status']} expected={check['expected']} actual={check['actual']}"
        )
    print(
        f"[summary] status={report['summary']['status']} "
        f"failed={report['summary']['failed_checks']}/{report['summary']['total_checks']}"
    )
    if report["summary"]["status"] != "pass":
        sys.exit(2)


def main():
    parser = argparse.ArgumentParser(description="Raw-data analysis metrics for ETL explainability")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p1 = sub.add_parser("analyze-accidents")
    p1.add_argument("--analysis-json", required=True)
    p1.add_argument("--raw-csv", required=True)
    p1.add_argument("--progress-every", type=int, default=250000)
    p1.add_argument("--top-issues", type=int, default=10)
    p1.set_defaults(func=cmd_analyze_accidents)

    p2 = sub.add_parser("analyze-air")
    p2.add_argument("--analysis-json", required=True)
    p2.add_argument("--raw-dir", required=True)
    p2.add_argument("--start-year", type=int, default=2016)
    p2.add_argument("--end-year", type=int, default=2023)
    p2.add_argument("--progress-every", type=int, default=50000)
    p2.add_argument("--top-issues", type=int, default=10)
    p2.set_defaults(func=cmd_analyze_air)

    p3 = sub.add_parser("validate-db")
    p3.add_argument("--analysis-json", required=True)
    p3.add_argument("--output-json", required=True)
    p3.set_defaults(func=cmd_validate)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
