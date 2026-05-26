# Naloga 6 Overview

This document gives a short visual overview of the Superset environment and the KPI dashboards prepared for the assignment. It is written as a baseline markdown file so it can later be converted into a PDF report.

## Superset Environment

The dashboard work is done in Apache Superset. Superset is connected directly to the PostgreSQL data warehouse through the `dw` database connection.

![Superset database connection](screenshots/superset-10-databases.png)

The KPI charts use virtual datasets in Superset. These datasets are based on SQL files from `naloga6/sql/`. They keep the warehouse as the source of truth and let Superset apply dashboard filters at query time.

![Superset KPI datasets](screenshots/superset-20-datasets.png)

The chart list shows the generated KPI charts. It includes table-preview charts for SQL inspection and graphical charts used on the dashboards.

![Superset KPI charts](screenshots/superset-30-charts.png)

The dashboard list shows the published dashboards used for this assignment:

- KPI 1 - Accident Frequency Dashboard
- KPI 2 - Accident Duration Dashboard
- KPI 3 - Air Quality Dashboard
- Dashboard 4 - Accidents and Air Quality Relationship

![Superset dashboards](screenshots/superset-40-dashboards.png)

## KPI 1: Accident Frequency

The first dashboard focuses on accident counts. It answers when and where accidents are most frequent, and how accident volume changes by severity.

The unfiltered view shows the full accident dataset. The dashboard includes:

- a KPI card with monthly accident count and trend;
- a monthly accident-count trend chart;
- weekday and hour accident patterns;
- accident counts split by severity over time;
- top counties by accident count.

![KPI 1 accident frequency without filters](screenshots/db-kpi1-accident-frequency-nofilters.png)

The filtered view shows the same charts after applying a time range, selected states, selected counties, and selected severity levels. The charts recalculate from the filtered data, so the large number, trend, weekday/hour chart, severity chart, and county ranking all describe the selected context.

![KPI 1 accident frequency with filters](screenshots/db-kpi1-accident-frequency-filtered.png)

This dashboard is useful for finding accident concentration by time and geography. It also shows how filters narrow the analysis from national-level data to a smaller local context.

## KPI 2: Accident Duration

The second dashboard focuses on accident duration. During inspection, average duration was not readable enough because a few very long events dominated the chart scale. The dashboard was therefore changed to use median duration and p90 duration as the main visible duration measures. The outliers remain in the data, but they no longer hide the normal pattern.

The unfiltered view includes:

- a KPI card for median accident duration;
- a monthly trend with median duration and p90 duration;
- median duration by weather condition;
- median duration by severity and primary road signal;
- top counties by accident count.

![KPI 2 accident duration without filters](screenshots/db-kpi2-accident-duration-nofilters.png)

The California-filtered view shows how the same dashboard changes when a state filter is applied. The charts now describe California only, and the county ranking becomes a California county ranking.

![KPI 2 accident duration filtered to California](screenshots/db-kpi2-accident-duration-filtered-ca.png)

The weather-filtered view shows a focused case for the `Tornado` weather condition. This is a small and unusual subset of the data. It demonstrates that the dashboard can drill into rare conditions without removing outliers from the source data.

![KPI 2 accident duration filtered to tornado weather](screenshots/db-kpi2-accident-duration-filtered-tornado.png)

This dashboard is useful for comparing typical duration across weather, severity, road signal, and geography. It also gives accident volume context through the top-county chart.

## KPI 3: Air Quality

The third dashboard focuses on bad-air AQI observations. Bad air is defined as `AQI > 100`, following the assignment proposal.

The unfiltered view includes:

- a KPI card for bad-air AQI share;
- a trend chart comparing average AQI and bad-air share;
- counties ranked by bad-air share;
- a donut chart showing which defining parameter contributes to bad-air observations.

![KPI 3 air quality without filters](screenshots/db-kpi3-air-quality-nofilters.png)

The filtered view shows the dashboard after applying a time range, a state filter, and a county selection. The county ranking and defining-parameter chart now describe only the selected New York counties and selected period.

![KPI 3 air quality with filters](screenshots/db-kpi3-air-quality-filtered.png)

This dashboard is useful for seeing where bad-air observations occur and which pollutant parameter is most often responsible for those observations.

## Dashboard 4: Accidents and Air Quality Relationship

The final dashboard combines accident and air-quality measures. It works at state/month grain and is meant for relationship analysis, not causal proof.

The unfiltered view shows the overall relationship between accident measures and bad-air share:

- correlation between accident count and bad-air share;
- correlation between average accident duration and bad-air share;
- correlation between severe accident share and bad-air share;
- scatter plots for accident count and duration against bad-air share;
- a state correlation ranking;
- a monthly comparison of accident count and bad-air percent.

![Combined accidents and air quality without filters](screenshots/db-combo-accidents-air-quality-nofilters.png)

The filtered view applies a time range and selected states. The correlation cards and charts recompute from the selected state/month observations. In this example, the selected states show weak negative correlations.

![Combined accidents and air quality with filters](screenshots/db-combo-accidents-air-quality-filtered.png)

The combined dashboard should be read carefully. A positive correlation means two measures tend to rise together. A negative correlation means one tends to rise while the other falls. Values near zero mean there is no strong linear relationship in the selected data. These charts describe association only; they do not prove that air quality causes accident changes.

## Summary

The Superset setup now contains a complete dashboard set for the assignment:

- KPI 1 shows accident frequency.
- KPI 2 shows accident duration using median and p90 duration.
- KPI 3 shows bad-air AQI share.
- Dashboard 4 compares accident measures with air-quality measures.

All dashboards use warehouse-backed virtual datasets. Dashboard filters and cross-filtering are configured for the visible chart dimensions. Outliers are kept in the data, and the visual choices are adjusted where needed so the dashboards remain readable.
