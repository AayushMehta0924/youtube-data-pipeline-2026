# Interview Prep: YouTube Trending Data Pipeline

## Architecture & Design

**Q1: Walk me through your project end-to-end.**
A: It's a serverless AWS pipeline that ingests YouTube trending video data — both a historical Kaggle dataset and live pulls from the YouTube Data API — and moves it through a medallion architecture. Raw data lands in a Bronze S3 bucket. A Lambda function and a Glue/PySpark job clean and reshape it into Parquet in Silver. Before it's trusted, a Data Quality Lambda runs checks (row counts, nulls, schema, value ranges, freshness) against Silver via Athena, and blocks progress if anything fails. If it passes, another Glue job aggregates Silver into three Gold analytics tables — trending, channel, and category level. Athena and QuickSight sit on top for querying. AWS Step Functions orchestrates the whole thing end-to-end with retries, parallel branches, and failure notifications via SNS.

**Q2: Why medallion architecture (bronze/silver/gold) instead of just cleaning data once and storing it?**
A: Separation of concerns and recoverability. Bronze is untouched raw data — if a downstream transformation has a bug, I can always reprocess from Bronze without re-fetching from the source. Silver is the "trusted, structured" layer used broadly. Gold is business-specific, pre-aggregated, and optimized for the exact queries the business asks (per-region trends, channel rankings, category share) rather than making every consumer re-derive those aggregates themselves.

**Q3: Why did you use both Lambda and Glue instead of just one or the other?**
A: I matched the tool to the size of the job. Lambda is cheap and simple for the small, delicate transform — the JSON category-reference files are tiny, so a lightweight function does the job. But the actual video statistics are large, and the raw data comes in two different shapes (old Kaggle CSV schema vs. live YouTube API JSON schema) that need real data-processing power to unify, clean, and deduplicate. That's a Spark job, and AWS Glue gives you serverless Spark without managing a cluster — so I used it for both the Bronze→Silver cleaning and the Silver→Gold aggregation, which both involve large-scale group-bys and joins.

**Q4: Why Step Functions instead of, say, cron jobs calling each script in sequence?**
A: A few reasons. First, dependency management — some steps can run in parallel (the JSON transform and the CSV Glue job don't depend on each other) and Step Functions expresses that natively instead of me hand-rolling parallelism. Second, built-in retry/backoff per step, instead of writing my own retry logic in every script. Third, branching logic — the pipeline needs to make a real decision ("did data quality pass?") and route differently based on it; that's a first-class `Choice` state, not an `if` buried in a script. And finally, visibility: you get a visual execution graph and history for free, which is much easier to debug than grepping through separate cron logs.

## AWS Services & Concepts

**Q5: What's the difference between Amazon Athena and a traditional database?**
A: Athena doesn't store any data itself — it's a query engine that reads files directly from S3 using the Glue Data Catalog as its schema/metadata layer, and you're billed per byte scanned, not for storage or a running server. A traditional database (or a warehouse like Redshift) owns and manages the actual storage, indexes data for performance, and runs a persistent compute cluster. Athena trades some query performance for zero infrastructure management and pay-per-query cost — which is the right trade for ad-hoc/periodic analytics like this, but not for something needing constant low-latency queries.

**Q6: What does a Glue Crawler actually do, and why do you need it?**
A: It scans files in S3, infers their schema (column names, types, partition structure), and registers that as a table in the Glue Data Catalog. Without it, Athena or Glue jobs have no idea what's inside your S3 files or how they're structured — you'd have to manually define the schema. In my pipeline, the Bronze layer needs a crawler since raw files land without any catalog entry; the Silver and Gold Glue jobs actually register their own tables as part of the write (`enableUpdateCatalog=True`), so they don't need a separate crawler run afterward.

**Q7: Why store data as Parquet instead of keeping CSV/JSON?**
A: Parquet is columnar and compressed, so both storage cost and query performance improve significantly — Athena only reads the columns a query actually needs instead of scanning entire rows, and Snappy compression cuts file size. It's also strongly typed, versus CSV which is just strings until something casts it. Given Athena charges per byte scanned, using Parquet directly reduces query cost.

**Q8: Explain your IAM setup. Why not just use one admin role for everything?**
A: I gave each service its own role scoped to only what it needs — least privilege. The Lambda role can read/write specific S3 buckets, touch specific Glue Catalog actions, publish to one SNS topic, and run Athena queries — nothing else. The Glue role has similar but slightly broader S3 access since it touches bronze/silver/gold/script buckets. Step Functions has its own role just to invoke Lambda, start Glue jobs, and publish to SNS. If any one of these were compromised or misconfigured, the blast radius is limited to exactly what that role can do — versus one admin role, where any bug or leak has full account access.

**Q9: What's an S3 lifecycle rule, and where did you use one?**
A: A lifecycle rule automatically transitions or deletes objects based on age, without any code running — it's a policy on the bucket itself. I used one on the Bronze bucket to move raw data older than 90 days into S3 Glacier, a much cheaper cold-storage tier with slower retrieval. Bronze data isn't queried often once it's been processed into Silver/Gold, so this cuts storage cost for data I probably don't need quickly but still want to retain.

## Data Engineering Specifics

**Q10: How did you handle the fact that your data came in two different schemas (Kaggle CSV vs. live API JSON)?**
A: In the Bronze→Silver Glue job, I detect which format a given batch is in by checking for the presence of API-specific columns (like `snippet.title`), then branch into two separate `select()` transformations that map each format's columns onto one common target schema — same column names and types regardless of source. That way everything downstream (Silver, Gold, quality checks) only ever deals with one unified shape.

**Q11: How do you handle duplicate records — e.g., a video that's still trending across multiple ingestion runs?**
A: I use a Spark window function partitioned by `video_id + region + trending_date`, ordered by `_processed_at` descending, and keep only row number 1 per group. It's effectively "keep the most recent copy per logical key" — done natively in Spark rather than a separate dedup pass.

**Q12: How does your Data Quality gate actually work, and what happens on failure?**
A: A Lambda samples up to 10,000 rows per Silver table via Athena and runs five checks: minimum row count, null percentage on critical columns, expected-schema presence, sane value ranges (no negative views), and data freshness. It returns a `quality_passed` boolean plus a details payload. Step Functions' `Choice` state reads that boolean directly — that field is effectively a contract between the Lambda and the state machine. If it's false, the pipeline routes to a failure-notification branch via SNS and the Gold aggregation job simply never runs, so nothing downstream ever sees unvalidated data.

**Q13: How do your writes stay idempotent — what happens if the same Lambda runs twice on the same data?**
A: The Silver writes use `mode="overwrite_partitions"` (via AWS Wrangler) — re-running the same input replaces that specific partition (e.g., one region) rather than appending duplicate rows. Combined with the dedup window function in the Glue job, reprocessing the same batch twice produces the same end state, not double-counted data.

**Q14: Why do you broadcast the category lookup table in your join instead of a normal join?**
A: The category-reference table is tiny (a few dozen rows) compared to the video statistics table, which can be large. A broadcast join ships that small table to every Spark executor instead of shuffling the much larger stats table across the cluster to align join keys — shuffling is expensive, and broadcasting a small table avoids it entirely. It's a standard optimization for exactly this "big table joined to small table" shape.

## Debugging & Operations

**Q15: Tell me about a bug you hit and how you debugged it.**
A: I hit a `numpy.core` import error when testing my Data Quality Lambda — turned out the Lambda layer I'd attached (`AWSSDKPandas-Python37`) was built for Python 3.7, but my function's runtime was Python 3.14, so the compiled numpy binaries were completely ABI-incompatible with the interpreter trying to load them. I fixed it by swapping in AWS's managed layer version built specifically for Python 3.14. Right after that I hit an `AccessDeniedException` on `athena:GetWorkGroup` — my IAM policy only granted `StartQueryExecution`/`GetQueryExecution`/`GetQueryResults`, but `awswrangler`'s Athena helper calls `GetWorkGroup` first to resolve the query's output location, so I added that specific permission. Both were classic "the error message names the exact missing piece" bugs — read the actual exception, don't guess.

**Q16: How would you monitor this pipeline in production?**
A: CloudWatch already captures logs from every Lambda invocation and Glue job run. I'd add CloudWatch Alarms on top of specific log patterns or Step Functions execution failures to page someone automatically instead of relying on someone reading the SNS email. I'd also track Glue job duration and Athena bytes-scanned over time — a jump in either usually signals either a data volume change or a regression in a transform.

## System Design / Scaling

**Q17: This currently handles 10 regions. How would you scale it to 100 regions or hourly ingestion?**
A: The architecture itself doesn't change — S3 partitioning by region already isolates each region's data, so adding more just means more partitions, not new code paths. The two things I'd watch: Lambda's ingestion loop is currently sequential per region, so at high region counts I'd parallelize those API calls (or fan out via Step Functions Map state) to avoid hitting the Lambda timeout. And the Glue jobs' worker count (`NumberOfWorkers`) would need to scale with data volume — that's a config change, not a rewrite.

**Q18: What would you change if you were rebuilding this for a real company today?**
A: Three things. One, Infrastructure as Code (Terraform/CDK) instead of manually clicking through the console — reproducibility and version control for the infra itself, not just the code. Two, I'd move quality thresholds and region lists out of hardcoded environment variables into a config table or Parameter Store, so business rules can change without redeploying. Three, I'd add automated tests for the Glue transform logic (e.g., using small local Spark test fixtures) rather than only validating by running the actual job against real data in AWS.
