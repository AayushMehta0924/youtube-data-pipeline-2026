# YouTube Trending Data Pipeline

A serverless AWS data pipeline that ingests YouTube trending video data, moves it through a
bronze → silver → gold medallion architecture, and exposes it for analytics via Athena and
QuickSight.

![Architecture diagram](Youtube_Trending_Data_Pipeline.png)

## Architecture

**Data Sources**
- YouTube Data API (via Amazon EventBridge on a schedule)
- Kaggle historical dataset (via a local Python/CLI upload)
- Amazon S3 Glacier (lifecycle-archived raw data)

**Bronze layer (raw data)** — `aayush-yt-data-pipeline-bronze-us-east-1-dev`
Raw JSON/CSV lands here untouched, partitioned by `region=`. An AWS Glue Crawler catalogs it.

**Silver layer (cleansed)** — `aayush-yt-data-pipeline-silver-us-east-1-dev`
- AWS Lambda transforms raw JSON reference data into Parquet.
- AWS Glue (Cleansing ETL) transforms the CSV/JSON video stats into Parquet.
- Registered in the Glue Data Catalog.

**Data Quality Gate**
An AWS Lambda validation step checks the silver output. Failures publish to Amazon SNS and
loop back for reprocessing; passing data proceeds to gold.

**Gold layer (business aggregations)** — `aayush-yt-data-pipeline-gold-us-east-1-dev`
AWS Glue aggregation ETL produces `trending_analytics`, `channel_analytics`, and
`category_analytics` tables (Parquet), cataloged in Glue.

**Analytics / Consumption**
Amazon Athena and Amazon QuickSight query the gold tables.

**Cross-cutting**
- AWS IAM — roles and permissions (see `iam_permissions/`)
- Amazon SNS — failure/success alerts
- Amazon CloudWatch — logging and monitoring
- AWS Step Functions — orchestrates: Ingestion → Wait → Silver transforms (parallel) →
  Data Quality check → Gold aggregation → SNS success notification

## Repo layout

```
iam_permissions/   IAM policy JSON for Lambda/Glue access to S3, SNS, Athena
glue_jobs/
  bronze_to_silver_statistics.py   Silver layer: cleanses/dedupes bronze video stats to Parquet
  silver_to_gold_analytics.py      Gold layer: builds trending/channel/category analytics tables
lambdas/
  youtube_api_ingestion/   Bronze layer: pulls trending videos + categories from the YouTube API
  json_to_parquet/         Silver layer: converts raw JSON reference data to partitioned Parquet
data_quality/
  dq_lambda.py             Data Quality Gate: validates silver tables before gold aggregation
step_functions/
  pipeline_orchestration.json   State machine: ingestion -> silver (parallel) -> DQ gate -> gold -> SNS notify
scripts/
  aws_copy.sh              One-off bulk upload of the Kaggle CSV/JSON dataset to bronze
  information.md           Bucket names, Glue database names, SNS topic ARN
data/                      Raw Kaggle source files (git-ignored, not tracked)
```

## Build status

- [x] Bronze ingestion — bulk upload script for historical Kaggle data
- [x] Bronze ingestion — live YouTube Data API Lambda (scheduled via EventBridge)
- [x] IAM policies for S3 / Glue / SNS / Athena access
- [x] Silver — Lambda: JSON reference data → Parquet
- [x] Silver — Glue cleansing ETL for CSV video stats → Parquet
- [ ] Glue Crawlers (bronze) and Data Catalog registration
- [x] Data Quality Gate Lambda + SNS failure/success alerting
- [x] Gold — Glue aggregation ETL (trending / channel / category analytics)
- [x] Step Functions orchestration
- [ ] Athena queries / QuickSight dashboards
- [ ] CloudWatch logging & monitoring setup

## Commit conventions

This repo follows [Conventional Commits](https://www.conventionalcommits.org/):
`feat`, `fix`, `docs`, `chore`, `refactor`, etc., optionally scoped, e.g.
`feat(silver): add JSON-to-parquet lambda`.
