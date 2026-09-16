-- =============================================================================
-- 01_create_external_table_retail.sql
-- Crea las 4 tablas externas de Athena sobre los CSV crudos en S3.
-- En esta capa "raw" todas las fechas se mantienen como STRING: se castean
-- recién en la capa Parquet (ver 02_ctas_parquet_partitioned.sql), que es
-- donde conviene aplicar tipos porque ya no se vuelve a re-parsear el CSV.
--
-- NOTA SOBRE EL SERDE: se usa OpenCSVSerde (org.apache.hadoop.hive.serde2.OpenCSVSerde)
-- en vez de ROW FORMAT DELIMITED con la cláusula QUOTE CHAR. Athena/Hive NO
-- soporta QUOTE CHAR como cláusula suelta de ROW FORMAT DELIMITED — esa
-- sintaxis rompe al ejecutar el DDL. OpenCSVSerde sí maneja correctamente
-- comillas y caracteres de escape dentro de campos CSV (por ejemplo,
-- "Description" en Online Retail II trae comas dentro del texto libre).
-- Las propiedades de separador/comilla/escape van dentro de
-- WITH SERDEPROPERTIES (...), y con este SerDe todas las columnas deben
-- declararse como STRING (los cast a tipos numéricos/fecha reales se hacen
-- después, en el CTAS a Parquet del script 02).
--
-- Reemplaza s3://micael-growth-funnel/ por tu bucket real (el mismo usado en
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
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://micael-growth-funnel/raw/online_retail/'
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
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://micael-growth-funnel/raw/product_events/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- -----------------------------------------------------------------------------
-- 3. Resultados de test A/B (dato sintético)
-- -----------------------------------------------------------------------------
-- Nota: con OpenCSVSerde todas las columnas se leen como string, incluso
-- "converted" (que en la capa raw original era int). El cast a INT se hace
-- en las queries de análisis (athena/05_ab_test_analysis.sql) o se puede
-- castear en un CTAS intermedio si se prefiere.
CREATE EXTERNAL TABLE IF NOT EXISTS growth_funnel.raw_ab_test (
    customer_id   string,
    variant       string,
    converted     string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://micael-growth-funnel/raw/ab_test/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- -----------------------------------------------------------------------------
-- 4. Costos de adquisición por canal y mes (dato sintético, para CAC)
-- -----------------------------------------------------------------------------
-- Nota: mismo caso — "acquisition_cost_pen" queda como string en esta capa
-- raw (antes era double); se castea en las queries de negocio (athena/08).
CREATE EXTERNAL TABLE IF NOT EXISTS growth_funnel.raw_acquisition_costs (
    channel                string,
    month                  string,
    acquisition_cost_pen   string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION 's3://micael-growth-funnel/raw/acquisition_costs/'
TBLPROPERTIES ('skip.header.line.count'='1');
