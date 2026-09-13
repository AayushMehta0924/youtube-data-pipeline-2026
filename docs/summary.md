# Day One: The Data Factory

*A story-format tour of the YouTube trending-data pipeline, room by room, for anyone new to AWS or data engineering.*

Your manager walks you to a whiteboard and says: *"We want to know what's trending on YouTube — which videos, which channels, which categories are winning, across 10 countries. Build me a factory that makes that happen, automatically, every few hours, forever."*

That's the whole assignment. Let's build it together, one room at a time.

---

## Room 01 — The Warehouse

Before you can process anything, you need somewhere to put raw stuff. So step one: you rent a warehouse. Not a small one — an infinite one, where you only pay for the shelf space you actually use.

You don't dump everything on one big pile though. You set up **three loading bays**:
- **Bronze bay** — raw, untouched stuff, exactly as it arrived
- **Silver bay** — stuff that's been cleaned and organized
- **Gold bay** — finished, ready-to-sell products

This three-bay layout has a name: **medallion architecture**. Nobody's being fancy — it's just "don't mix raw material with finished product."

> **Nameplate:** Amazon S3

## Room 02 — The Trucks Arrive

Two trucks pull up to the Bronze bay.

**Truck 1** is a one-time historical delivery — someone already collected years of old YouTube trending data (from Kaggle) and drives it in once, using a simple hand-written delivery slip (a bash script running `aws s3 cp` — just "copy this file here" repeated 20 times).

**Truck 2** is different — it's automatic and never stops. Every few hours, a **robot driver** (AWS Lambda) wakes up on its own schedule (set by **Amazon EventBridge**, basically a cloud alarm clock), drives to YouTube's front desk (the YouTube Data API), asks "what's trending right now, in each of these 10 countries?", and drives the answer straight into the Bronze bay as raw JSON files.

Neither truck is allowed past the front gate without an ID badge. That badge system is **AWS IAM** — every worker and every robot in this factory carries a badge that says exactly what they're allowed to touch and nothing more. The Lambda robot's badge says "you may read/write these specific shelves, nothing else." No badge, no entry.

> **Nameplate:** AWS Lambda · Amazon EventBridge · AWS IAM

## Room 03 — The Labeling Robot

Now you've got hundreds of raw crates sitting in Bronze. Nobody labeled them. If someone asks "how many videos do we have for India?" — you'd have to physically open every crate to find out. Painful.

So you deploy a **labeling robot** (a Glue Crawler) that walks the aisles, peeks inside the crates, and writes down what it finds — column names, data types, how many rows — into a big shared clipboard called the **Glue Data Catalog**. Now that clipboard is the single source of truth: "crate shelf X has columns video_id, views, likes... partitioned by country."

Because that clipboard exists, anyone can now walk up with a **query terminal** (Amazon Athena) and just *ask questions in SQL* — "show me videos from Canada" — without moving a single crate. Athena doesn't store anything itself; it just reads straight off the shelf using the clipboard as a map.

**First inspection:** You try this on the raw Bronze crates and... yikes. The dates are formatted like `17.14.11` (what does that even mean?), some video titles are missing, and the JSON crates are so oddly nested Athena can't even read them yet. Classic raw data. Time for the cleaning floor.

> **Nameplate:** AWS Glue Crawler · AWS Glue Data Catalog · Amazon Athena

## Room 04 — The Cleaning Floor

Two cleaning stations run **at the same time**, because they handle different-sized jobs:

**Station A — the small-parts bench.** The category-name files (tiny JSON lists like "24 = Entertainment, 10 = Music") are small and simple. You don't need heavy machinery — one nimble worker (a Lambda function) unpacks them, removes duplicates, and repacks them neatly as **Parquet** (a compact, organized crate format that's much faster to search than loose JSON/CSV).

**Station B — the industrial line.** The actual video statistics are huge, messy, and arrive in two different shapes (old CSV format vs. new live-API JSON format). This needs real machinery — **AWS Glue running Apache Spark**, a serverless big-data engine that can chew through massive files in parallel across many machines without you ever having to buy or configure those machines. It figures out which shape each file is, renames columns to match, fixes those weird dates, drops duplicate videos, fills in missing numbers, and calculates new useful stats like "engagement rate."

Both stations write their finished work into the **Silver bay**, in the tidy Parquet format, and — importantly — they *also* update that shared clipboard (Glue Catalog) themselves as they write, so nobody needs to send the labeling robot back around.

> **Nameplate:** AWS Lambda · AWS Glue (PySpark)

## Room 05 — The Quality Inspector

Before anything from Silver is allowed anywhere near customers, it passes through a strict inspector's booth (another Lambda, running data quality checks). The inspector pulls a sample and asks five questions:

1. Is there *enough* data? (not some empty, broken batch)
2. Are important fields missing too often?
3. Are all the expected columns even there?
4. Do the numbers make sense? (a video can't have *negative* views)
5. Is this data actually recent, or stale?

The inspector runs these checks by literally querying the Silver shelf with Athena — same query terminal as before, just used programmatically.

**If something's off:** The inspector pulls a **fire alarm** (Amazon SNS) that instantly emails the team: *"Hey, quality check failed, here's exactly why."* And critically — **the line stops there**. Bad data never reaches the next room.

> **Nameplate:** AWS Lambda · Amazon Athena · Amazon SNS

## Room 06 — The Packaging Floor

If quality passes, the clean Silver material moves to the final assembly floor — another Glue/Spark job, but this time its job isn't cleaning, it's **combining and summarizing** into finished, sellable products. It builds three finished goods:

- **`trending_analytics`** — a daily digest per country: how many videos trended, total views, average engagement
- **`channel_analytics`** — a leaderboard: which channels win the most, ranked per region
- **`category_analytics`** — a market-share report: is Music beating Entertainment today, and by how much?

These land in the **Gold bay**, also as Parquet, also auto-registered on the clipboard — ready for business use.

> **Nameplate:** AWS Glue (PySpark)

## Room 07 — The Storefront

Now anyone in the company — no coding required — can walk up to the storefront. Analysts run SQL through **Athena** directly on Gold tables. Executives who don't want to write SQL at all get a **QuickSight** dashboard — drag-and-drop charts sitting on top of the same Gold data. Same product, different counters.

> **Nameplate:** Amazon Athena · Amazon QuickSight

## Room 08 — The Foreman

Here's the twist: none of the above happens by someone manually walking to each station and pressing "start." That's the foreman's job — **AWS Step Functions**.

The foreman holds a clipboard with the exact plan:

```
1. Tell the truck robot to fetch new data.
2. Wait 10 seconds (let the warehouse system catch up).
3. Send BOTH cleaning stations at once — they don't need each other.
4. Once both are done, call the inspector.
5. Inspector says pass? → send it to packaging.
   Inspector says fail? → ring the alarm, stop here.
6. Packaging finishes → ring the "all clear, we're done" bell.
```

If any single step breaks, the foreman doesn't just crash — it retries a couple of times automatically (machines glitch sometimes), and if it still fails, it rings the *right* alarm for *that* specific failure, so whoever's on call knows exactly which station broke without digging through logs.

And every worker in this building — Lambda, Glue, the foreman itself — keeps a running logbook (**Amazon CloudWatch**) of everything it did, in case someone needs to investigate later.

> **Nameplate:** AWS Step Functions · Amazon CloudWatch

## Room 09 — The Archive

One more room you didn't see yet: old Bronze crates you haven't touched in 90 days? No point paying warehouse-shelf prices for those forever. A standing rule automatically moves them into a **deep archive vault** (S3 Glacier) — much cheaper rent, slower to retrieve, perfect for "we probably won't need this, but compliance says keep it."

> **Nameplate:** Amazon S3 Glacier

---

## Shift Summary

Trucks bring raw YouTube data in → a robot labels it → cleaning stations fix and organize it → an inspector checks it's good → a packaging floor turns it into 3 business reports → a storefront lets people query/view it → a foreman runs the entire building on autopilot → old stuff gets archived. That's the whole factory.

## Decoder Ring

Same tour, real vocabulary — for when you need to say this out loud in a meeting.

| In the story | In real life | What it's for |
|---|---|---|
| Warehouse / bays | Amazon S3 | Object storage, split into bronze/silver/gold buckets |
| ID badge system | AWS IAM | Roles & policies controlling exactly what each service can touch |
| Delivery trucks | Bash script + Lambda | One-off historical upload, plus a live scheduled ingestion function |
| Alarm clock | Amazon EventBridge | Triggers the ingestion Lambda on a recurring schedule |
| Labeling robot | AWS Glue Crawler | Scans files and registers their schema automatically |
| Shared clipboard | Glue Data Catalog | Central metadata store other tools read to find your data |
| Query terminal | Amazon Athena | Runs SQL directly on S3 files, no loading required |
| Small-parts bench | AWS Lambda | Lightweight transform for small reference-data files |
| Industrial cleaning line | AWS Glue (PySpark) | Serverless Spark for large-scale cleaning & aggregation |
| Inspector's booth | Data quality Lambda | Row count, null%, schema, range & freshness checks |
| Fire alarm | Amazon SNS | Publishes success/failure notifications by email |
| Dashboard counter | Amazon QuickSight | No-code charts & dashboards on top of Athena |
| Foreman | AWS Step Functions | Orchestrates every step, in order, with retries & branching |
| Logbook | Amazon CloudWatch | Centralized logs from every Lambda & Glue run |
| Deep archive vault | Amazon S3 Glacier | Cheap cold storage for data older than 90 days |

---

*youtube-data-pipeline-2026 · project summary · rooms 01–09*
