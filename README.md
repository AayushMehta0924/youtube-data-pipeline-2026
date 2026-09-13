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

## Tools & Services

### AWS services

| Service | What it does here |
|---|---|
| Amazon S3 | Object storage holding the Bronze/Silver/Gold data lake plus scripts and Athena query results |
| AWS Lambda | Serverless compute for ingestion (YouTube API), JSON→Parquet transform, and data quality checks |
| AWS Glue (ETL Jobs) | Serverless PySpark for the heavy Bronze→Silver cleaning and Silver→Gold aggregation |
| AWS Glue Data Catalog | Central metadata store (table schemas/partitions) so Athena/Glue can find and query S3 data |
| AWS Glue Crawler | Scans S3 files and auto-registers their schema into the Data Catalog |
| Amazon Athena | Serverless SQL query engine that reads S3 data directly via the Glue Catalog, no data loading needed |
| Amazon QuickSight | BI/dashboard tool for visualizing the Gold analytics tables (optional, on top of Athena) |
| AWS Step Functions | Orchestrator/state machine that runs the whole pipeline in the right order, with retries and branching |
| Amazon EventBridge | Scheduler that triggers the ingestion Lambda (and can trigger Step Functions) on a recurring interval |
| Amazon SNS | Publishes success/failure email notifications at each pipeline stage |
| Amazon CloudWatch | Captures logs from every Lambda/Glue run for debugging and monitoring |
| AWS IAM | Access control — defines roles and least-privilege policies so services can call each other securely |
| Amazon S3 Glacier | Cold storage tier; lifecycle rule archives old raw Bronze data here after 90 days |

### IAM roles / policies

| Role/Policy | What it grants |
|---|---|
| YT data pipeline Lambda role | Execution role attached to all 3 Lambdas; grants S3, Glue Catalog, SNS, and Athena access |
| YT data pipeline Glue role | Execution role for both Glue ETL jobs; grants S3 and Glue Catalog access |
| YT data pipeline Step Functions role | Lets the state machine invoke Lambda, start Glue jobs, and publish to SNS |
| `s3_lambda_yt_pipeline_policy.json` | Inline policy: S3 (bronze/silver/Athena-results), Glue Catalog, SNS publish, Athena query actions |
| `yt-data-pipeline-glue-access.json` | Inline policy: broader S3 access (bronze/silver/gold/script buckets) for Glue jobs |
| `yt-data-pipeline-sfn-access.json` | Inline policy: lets Step Functions invoke Lambdas, run/monitor Glue jobs, publish to SNS |

### Languages / libraries

| Tool | What it's used for |
|---|---|
| Python 3 | Language for all Lambda functions and the DQ logic |
| PySpark | Spark's Python API, used inside both Glue ETL jobs for large-scale transforms |
| Pandas | Small-scale JSON flattening/dedup in Lambda (reference data, DQ sampling) |
| AWS Wrangler (awswrangler) | Pandas-to-AWS glue library — simplifies writing Parquet + Glue Catalog registration, and running Athena queries from Python |
| Boto3 | AWS SDK for Python — used for direct S3/SNS calls in the Lambdas |
| SQL (via Athena) | Ad-hoc querying of raw and Gold data for analytics/validation |

### Data sources

| Source | Description |
|---|---|
| YouTube Data API v3 | Live source of trending videos + category metadata, pulled by the ingestion Lambda |
| Kaggle YouTube Trending dataset | Historical CSV/JSON dataset used to backfill Bronze via `aws_copy.sh` |

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
