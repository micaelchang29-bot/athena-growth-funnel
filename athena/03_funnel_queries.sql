-- =============================================================================
-- 03_funnel_queries.sql
-- Funnel transaccional sobre Online Retail II (dato real), usado como proxy
-- de un funnel de adquisición -> activación -> retención en un negocio
-- transaccional recurrente (como una fintech de pagos).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Fecha de primera compra por cliente + cohorte de adquisición (mes)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW growth_funnel.v_first_purchase AS
SELECT
    customer_id,
    MIN(invoice_date)                              AS first_purchase_date,
    date_trunc('month', MIN(invoice_date))         AS acquisition_cohort_month
FROM growth_funnel.online_retail_parquet
GROUP BY customer_id;

-- -----------------------------------------------------------------------------
-- 2) Clientes "activados": segunda compra dentro de 30 días de la primera
--    (usando LEAD() sobre las fechas de compra distintas de cada cliente)
-- -----------------------------------------------------------------------------
WITH purchase_dates AS (
    SELECT DISTINCT
        customer_id,
        date_trunc('day', invoice_date) AS purchase_day
    FROM growth_funnel.online_retail_parquet
),
ordered_purchases AS (
    SELECT
        customer_id,
        purchase_day,
        LEAD(purchase_day) OVER (PARTITION BY customer_id ORDER BY purchase_day) AS next_purchase_day
    FROM purchase_dates
),
first_purchase AS (
    SELECT customer_id, MIN(purchase_day) AS first_purchase_day
    FROM purchase_dates
    GROUP BY customer_id
),
activation AS (
    SELECT
        o.customer_id,
        fp.first_purchase_day,
        MAX(CASE
                WHEN o.purchase_day = fp.first_purchase_day
                     AND o.next_purchase_day IS NOT NULL
                     AND date_diff('day', o.purchase_day, o.next_purchase_day) <= 30
                THEN 1 ELSE 0
            END) AS activated
    FROM ordered_purchases o
    JOIN first_purchase fp ON fp.customer_id = o.customer_id
    GROUP BY o.customer_id, fp.first_purchase_day
)
SELECT
    customer_id,
    first_purchase_day,
    activated
FROM activation;

-- -----------------------------------------------------------------------------
-- 3) % de conversión en cada etapa: adquiridos -> activados -> retenidos
--    (retenido = compra en los 3 meses siguientes al mes de activación)
-- -----------------------------------------------------------------------------
WITH purchase_dates AS (
    SELECT DISTINCT customer_id, date_trunc('day', invoice_date) AS purchase_day
    FROM growth_funnel.online_retail_parquet
),
first_purchase AS (
    SELECT customer_id, MIN(purchase_day) AS first_purchase_day
    FROM purchase_dates
    GROUP BY customer_id
),
ordered_purchases AS (
    SELECT
        customer_id,
        purchase_day,
        LEAD(purchase_day) OVER (PARTITION BY customer_id ORDER BY purchase_day) AS next_purchase_day
    FROM purchase_dates
),
activation AS (
    SELECT
        fp.customer_id,
        fp.first_purchase_day,
        MAX(CASE
                WHEN o.purchase_day = fp.first_purchase_day
                     AND o.next_purchase_day IS NOT NULL
                     AND date_diff('day', o.purchase_day, o.next_purchase_day) <= 30
                THEN 1 ELSE 0
            END) AS activated
    FROM first_purchase fp
    JOIN ordered_purchases o ON o.customer_id = fp.customer_id
    GROUP BY fp.customer_id, fp.first_purchase_day
),
retention AS (
    SELECT
        a.customer_id,
        MAX(CASE
                WHEN a.activated = 1
                     AND pd.purchase_day > a.first_purchase_day
                     AND pd.purchase_day <= date_add('month', 3, a.first_purchase_day)
                THEN 1 ELSE 0
            END) AS retained
    FROM activation a
    LEFT JOIN purchase_dates pd ON pd.customer_id = a.customer_id
    GROUP BY a.customer_id
)
SELECT
    COUNT(DISTINCT a.customer_id)                                   AS clientes_adquiridos,
    SUM(a.activated)                                                AS clientes_activados,
    SUM(r.retained)                                                 AS clientes_retenidos,
    ROUND(100.0 * SUM(a.activated) / COUNT(DISTINCT a.customer_id), 2)   AS pct_activacion,
    ROUND(100.0 * SUM(r.retained) / NULLIF(SUM(a.activated), 0), 2)     AS pct_retencion_sobre_activados
FROM activation a
JOIN retention r ON r.customer_id = a.customer_id;
