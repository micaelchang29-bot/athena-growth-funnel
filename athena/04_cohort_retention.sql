-- =============================================================================
-- 04_cohort_retention.sql
-- Matriz de retención por cohortes sobre Online Retail II.
-- Filas = mes de adquisición (primera compra), columnas = mes N desde
-- adquisición, valores = % de la cohorte que compró en ese mes N.
-- Usa funciones de fecha del dialecto Trino/Presto (motor de Athena):
-- date_trunc, date_diff, date_add — no equivalentes de MySQL/Postgres.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Matriz de cohortes: % de retención por mes de cohorte y mes N
-- -----------------------------------------------------------------------------
WITH first_purchase AS (
    SELECT
        customer_id,
        date_trunc('month', MIN(invoice_date)) AS cohort_month
    FROM growth_funnel.online_retail_parquet
    GROUP BY customer_id
),
activity_months AS (
    SELECT DISTINCT
        customer_id,
        date_trunc('month', invoice_date) AS activity_month
    FROM growth_funnel.online_retail_parquet
),
cohort_activity AS (
    SELECT
        fp.cohort_month,
        fp.customer_id,
        date_diff('month', fp.cohort_month, am.activity_month) AS month_number
    FROM first_purchase fp
    JOIN activity_months am ON am.customer_id = fp.customer_id
    WHERE am.activity_month >= fp.cohort_month
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
),
cohort_counts AS (
    SELECT
        cohort_month,
        month_number,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM cohort_activity
    GROUP BY cohort_month, month_number
)
SELECT
    cc.cohort_month,
    cc.month_number,
    cs.cohort_customers,
    cc.active_customers,
    ROUND(100.0 * cc.active_customers / cs.cohort_customers, 2) AS pct_retained
FROM cohort_counts cc
JOIN cohort_size cs ON cs.cohort_month = cc.cohort_month
ORDER BY cc.cohort_month, cc.month_number;

-- -----------------------------------------------------------------------------
-- Alerta: retención del mes más reciente (month_number = 1) vs. promedio de
-- los 3 meses de cohorte anteriores. Marca si la caída supera 5 puntos
-- porcentuales.
-- -----------------------------------------------------------------------------
WITH first_purchase AS (
    SELECT
        customer_id,
        date_trunc('month', MIN(invoice_date)) AS cohort_month
    FROM growth_funnel.online_retail_parquet
    GROUP BY customer_id
),
activity_months AS (
    SELECT DISTINCT
        customer_id,
        date_trunc('month', invoice_date) AS activity_month
    FROM growth_funnel.online_retail_parquet
),
cohort_activity AS (
    SELECT
        fp.cohort_month,
        fp.customer_id,
        date_diff('month', fp.cohort_month, am.activity_month) AS month_number
    FROM first_purchase fp
    JOIN activity_months am ON am.customer_id = fp.customer_id
    WHERE am.activity_month >= fp.cohort_month
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
),
month1_retention AS (
    SELECT
        ca.cohort_month,
        ROUND(100.0 * COUNT(DISTINCT ca.customer_id) / cs.cohort_customers, 2) AS pct_retained_month1
    FROM cohort_activity ca
    JOIN cohort_size cs ON cs.cohort_month = ca.cohort_month
    WHERE ca.month_number = 1
    GROUP BY ca.cohort_month, cs.cohort_customers
),
ranked AS (
    SELECT
        cohort_month,
        pct_retained_month1,
        ROW_NUMBER() OVER (ORDER BY cohort_month DESC) AS rn
    FROM month1_retention
),
latest AS (
    SELECT cohort_month, pct_retained_month1 FROM ranked WHERE rn = 1
),
previous_avg AS (
    SELECT AVG(pct_retained_month1) AS avg_prev_3_months
    FROM ranked
    WHERE rn BETWEEN 2 AND 4
)
SELECT
    l.cohort_month                   AS mes_mas_reciente,
    l.pct_retained_month1            AS retencion_mes_mas_reciente,
    ROUND(p.avg_prev_3_months, 2)    AS retencion_promedio_3_meses_previos,
    ROUND(l.pct_retained_month1 - p.avg_prev_3_months, 2) AS diferencia_puntos_pct,
    CASE
        WHEN (p.avg_prev_3_months - l.pct_retained_month1) > 5 THEN 'ALERTA: caida > 5pp'
        ELSE 'OK'
    END AS estado
FROM latest l
CROSS JOIN previous_avg p;
