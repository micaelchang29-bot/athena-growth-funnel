-- =============================================================================
-- 02_ctas_parquet_partitioned.sql
-- CTAS (CREATE TABLE AS SELECT) para convertir las tablas raw (CSV/TEXTFILE)
-- a Parquet particionado por year/month.
--
-- Por qué Parquet particionado y no consultar el CSV crudo directamente:
--   - Parquet es columnar: Athena solo lee las columnas referenciadas en el
--     SELECT, no la fila completa como en un CSV de texto plano.
--   - Compresión columnar típica de 5-10x vs. CSV sin comprimir.
--   - El particionado por year/month permite "partition pruning": si una
--     query filtra por WHERE year=2024 AND month=3, Athena ni siquiera abre
--     los archivos de las demás particiones.
--   - Athena cobra por bytes escaneados (~$5 por TB). Pasar de CSV a Parquet
--     particionado en este dataset reduce el escaneo típico de una query de
--     funnel/cohortes en un 90-95%, lo que se traduce directamente en menor
--     costo y menor latencia.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Online Retail II -> Parquet particionado por year/month de invoice_date
-- -----------------------------------------------------------------------------
CREATE TABLE growth_funnel.online_retail_parquet
WITH (
    format = 'PARQUET',
    parquet_compression = 'SNAPPY',
    partitioned_by = ARRAY['year', 'month'],
    external_location = 's3://YOUR_BUCKET/curated/online_retail_parquet/'
) AS
SELECT
    invoice_no,
    stock_code,
    description,
    CAST(quantity AS INTEGER)                      AS quantity,
    CAST(date_parse(invoice_date, '%Y-%m-%d %H:%i:%s') AS TIMESTAMP) AS invoice_date,
    CAST(unit_price AS DOUBLE)                     AS unit_price,
    CAST(customer_id AS INTEGER)                   AS customer_id,
    country,
    CAST(total_price AS DOUBLE)                    AS total_price,
    CAST(year(date_parse(invoice_date, '%Y-%m-%d %H:%i:%s')) AS VARCHAR)  AS year,
    CAST(month(date_parse(invoice_date, '%Y-%m-%d %H:%i:%s')) AS VARCHAR) AS month
FROM growth_funnel.raw_online_retail;

-- -----------------------------------------------------------------------------
-- Product Events -> Parquet particionado por year/month de event_timestamp
-- -----------------------------------------------------------------------------
CREATE TABLE growth_funnel.product_events_parquet
WITH (
    format = 'PARQUET',
    parquet_compression = 'SNAPPY',
    partitioned_by = ARRAY['year', 'month'],
    external_location = 's3://YOUR_BUCKET/curated/product_events_parquet/'
) AS
SELECT
    user_id,
    channel,
    event_name,
    CAST(date_parse(substr(event_timestamp, 1, 19), '%Y-%m-%d %H:%i:%s') AS TIMESTAMP) AS event_timestamp,
    CAST(NULLIF(amount, '') AS DOUBLE)             AS amount,
    CAST(NULLIF(is_fraud, '') AS BOOLEAN)          AS is_fraud,
    NULLIF(kyc_result, '')                         AS kyc_result,
    CAST(year(date_parse(substr(event_timestamp, 1, 19), '%Y-%m-%d %H:%i:%s')) AS VARCHAR)  AS year,
    CAST(month(date_parse(substr(event_timestamp, 1, 19), '%Y-%m-%d %H:%i:%s')) AS VARCHAR) AS month
FROM growth_funnel.raw_product_events;

-- Después de crear las tablas particionadas, si en algún momento se cargan
-- nuevos archivos directamente en S3 (sin pasar por otro CTAS), correr:
-- MSCK REPAIR TABLE growth_funnel.online_retail_parquet;
-- MSCK REPAIR TABLE growth_funnel.product_events_parquet;
