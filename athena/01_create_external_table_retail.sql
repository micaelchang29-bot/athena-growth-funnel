-- =============================================================================
-- 01_create_external_table_retail.sql
-- Crea las 4 tablas externas de Athena sobre los CSV crudos en S3.
-- En esta capa "raw" todas las fechas se mantienen como STRING: se castean
-- recién en la capa Parquet (ver 02_ctas_parquet_partitioned.sql), que es
-- donde conviene aplicar tipos porque ya no se vuelve a re-parsear el CSV.
--
-- Reemplaza s3://YOUR_BUCKET/ por tu bucket real (el mismo usado en
-- scripts/upload_to_s3.py vía la variable ATHENA_GROWTH_BUCKET).
-- =============================================================================

CREATE DATABASE IF NOT EXISTS growth_funnel;

-- -----------------------------------------------------------------------------
-- 1. Online Retail II (dato real, proxy de funnel transaccional)
-- -----------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS growth_funnel.raw_online_retail (
    invoice_no     string,
    stock_code     string,
    description    string,
    quantity       string,
    invoice_date   string,
    unit_price     string,
    customer_id    string,
    country        string,
    total_price    string
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
QUOTE CHAR '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
STORED AS TEXTFILE
LOCATION 's3://YOUR_BUCKET/raw/online_retail/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- -----------------------------------------------------------------------------
-- 2. Eventos de producto (dato sintético, funnel de activación / engagement)
-- -----------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS growth_funnel.raw_product_events (
    user_id           string,
    channel           string,
    event_name        string,
    event_timestamp   string,
    amount            string,
    is_fraud          string,
    kyc_result        string
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
QUOTE CHAR '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
STORED AS TEXTFILE
LOCATION 's3://YOUR_BUCKET/raw/product_events/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- -----------------------------------------------------------------------------
-- 3. Resultados de test A/B (dato sintético)
-- -----------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS growth_funnel.raw_ab_test (
    customer_id   string,
    variant       string,
    converted     int
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
QUOTE CHAR '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
STORED AS TEXTFILE
LOCATION 's3://YOUR_BUCKET/raw/ab_test/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- -----------------------------------------------------------------------------
-- 4. Costos de adquisición por canal y mes (dato sintético, para CAC)
-- -----------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS growth_funnel.raw_acquisition_costs (
    channel                string,
    month                  string,
    acquisition_cost_pen   double
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
QUOTE CHAR '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
STORED AS TEXTFILE
LOCATION 's3://YOUR_BUCKET/raw/acquisition_costs/'
TBLPROPERTIES ('skip.header.line.count'='1');
