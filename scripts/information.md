Bronze Bucket Name: aayush-yt-data-pipeline-bronze-us-east-1-dev
Silver Bucket Name: aayush-yt-data-pipeline-silver-us-east-1-dev
Gold Bucket Name: aayush-yt-data-pipeline-gold-us-east-1-dev

Script Bucket Name: aayush-yt-data-pipeline-script-us-east-1-dev

SNS ARN: arn:aws:sns:us-east-1:432510057324:yt-data-pipeline-alerts-dev:b3c60bcf-fb3a-4e79-a002-309b18264aba

Glue Bronze: yt_pipeline_bronze_dev
Glue Silver: yt_pipeline_silver_dev
Glue Gold: yt_pipeline_gold_dev

--bronze_database yt_pipeline_bronze_dev
--bronze_table raw_statistics
--silver_bucket aayush-yt-data-pipeline-silver-us-east-1-dev
--silver_database yt_pipeline_silver_dev
--silver_table clean_statistics

--silver_database yt_pipeline_silver_dev
--gold_bucket aayush-yt-data-pipeline-gold-us-east-1-dev
--gold_database yt_pipeline_gold_dev
