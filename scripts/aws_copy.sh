# One-off bulk upload of the historical Kaggle YouTube-trending dataset into
# the Bronze S3 bucket. Run this once from inside the data/ folder (the file
# names below are relative — `cd data && bash ../scripts/aws_copy.sh`).
#
# Layout mirrors how the live YouTube API Lambda partitions data, so both
# sources land in a shape the Glue Crawler/Athena can read the same way:
#   raw_statistics/region=<code>/               -> per-region video CSVs
#   raw_statistics_reference_data/region=<code>/ -> per-region category JSON

# --- Video statistics CSVs, one per region ---
aws s3 cp CAvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=ca/CAvideos.csv
aws s3 cp DEvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=de/DEvideos.csv
aws s3 cp FRvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=fr/FRvideos.csv
aws s3 cp GBvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=gb/GBvideos.csv
aws s3 cp INvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=in/INvideos.csv
aws s3 cp JPvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=jp/JPvideos.csv
aws s3 cp KRvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=kr/KRvideos.csv
aws s3 cp MXvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=mx/MXvideos.csv
aws s3 cp RUvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=ru/RUvideos.csv
aws s3 cp USvideos.csv s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics/region=us/USvideos.csv

# --- Category ID reference JSON, one per region ---
aws s3 cp CA_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=ca/
aws s3 cp DE_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=de/
aws s3 cp FR_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=fr/
aws s3 cp GB_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=gb/
aws s3 cp IN_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=in/
aws s3 cp JP_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=jp/
aws s3 cp KR_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=kr/
aws s3 cp MX_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=mx/
aws s3 cp RU_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=ru/
aws s3 cp US_category_id.json s3://aayush-yt-data-pipeline-bronze-us-east-1-dev/youtube/raw_statistics_reference_data/region=us/
