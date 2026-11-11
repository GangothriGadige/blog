-- Managed: no EXTERNAL keyword, no explicit LOCATION
CREATE TABLE analytics.dim_channel (
  channel_key   INT,
  channel_name  STRING
)
STORED AS ORC;

-- External: EXTERNAL + LOCATION
CREATE EXTERNAL TABLE landing.raw_orders (
  order_id    STRING,
  order_ts    TIMESTAMP
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 's3://data-lake/landing/orders/';

-- Inspect what you already have
DESCRIBE FORMATTED analytics.dim_channel;
DESCRIBE FORMATTED landing.raw_orders;
