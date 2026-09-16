-- =============================================================================
-- 08_business_metrics.sql
-- 8 métricas de negocio y riesgo para una fintech de pagos, calculadas sobre
-- los eventos sintéticos de producto + costos de adquisición.
--
-- TABLAS USADAS:
--   - growth_funnel.product_events_parquet: para todo lo que requiere
--     aritmética de fechas (date_trunc, date_format) o sumar/promediar
--     "amount" y "is_fraud" — ya vienen tipados (TIMESTAMP, DOUBLE, BOOLEAN)
--     desde el CTAS de 02_ctas_parquet_partitioned.sql.
--   - growth_funnel.raw_acquisition_costs: NO tiene versión Parquet en este
--     proyecto (son solo 12 filas — 3 canales x 4-6 meses — el volumen no
--     justifica una tabla particionada aparte). Sigue siendo 100% STRING
--     porque viene de OpenCSVSerde, así que "acquisition_cost_pen" se
--     castea explícitamente a DOUBLE en cada query que la usa (métricas 1 y 7).
--     Si el dataset creciera a un tamaño real de producción, sí convendría
--     un CTAS a Parquet como el de las otras dos tablas.
--
-- NOTA SOBRE "month" EN raw_acquisition_costs: esta columna es un string
-- libre con formato 'YYYY-MM' generado en pandas (no es una columna de
-- partición de Hive), por lo que el JOIN contra
-- date_format(..., '%Y-%m') funciona directo sin casteos adicionales de
-- partición. Esto es distinto de las columnas year/month de las tablas
-- *_parquet, que sí son particiones STRING y deben compararse con
-- literales entre comillas (ver 04_cohort_retention.sql y
-- 02_ctas_parquet_partitioned.sql para ese patrón).
-- =============================================================================

-- ===== SENTENCIA 1: CAC por canal y mes = costo del canal / usuarios nuevos =====
WITH new_users AS (
    SELECT
        channel,
        date_trunc('month', event_timestamp)                        AS month_ts,
        date_format(date_trunc('month', event_timestamp), '%Y-%m')  AS month,
        COUNT(DISTINCT user_id)                                     AS nuevos_usuarios
    FROM growth_funnel.product_events_parquet
    WHERE event_name = 'signup'
    GROUP BY channel, date_trunc('month', event_timestamp)
)
SELECT
    nu.channel,
    nu.month,
    nu.nuevos_usuarios,
    CAST(ac.acquisition_cost_pen AS DOUBLE) AS acquisition_cost_pen,
    ROUND(CAST(ac.acquisition_cost_pen AS DOUBLE) / NULLIF(nu.nuevos_usuarios, 0), 2) AS cac_pen
FROM new_users nu
JOIN growth_funnel.raw_acquisition_costs ac
    ON ac.channel = nu.channel AND ac.month = nu.month
ORDER BY nu.month, nu.channel;

-- ===== SENTENCIA 2: tasa de aprobación/rechazo de KYC, general y por canal =====
SELECT
    channel,
    COUNT(*)                                                              AS total_kyc,
    SUM(CASE WHEN kyc_result = 'kyc_approved' THEN 1 ELSE 0 END)          AS aprobados,
    SUM(CASE WHEN kyc_result = 'kyc_rejected' THEN 1 ELSE 0 END)          AS rechazados,
    ROUND(100.0 * SUM(CASE WHEN kyc_result = 'kyc_approved' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_aprobacion,
    ROUND(100.0 * SUM(CASE WHEN kyc_result = 'kyc_rejected' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_rechazo
FROM growth_funnel.product_events_parquet
WHERE event_name = 'complete_kyc'
GROUP BY GROUPING SETS ((channel), ())
ORDER BY channel;

-- ===== SENTENCIA 3: vista de transacciones mensuales (base para métricas 3-8) =====
-- Correr esta CREATE VIEW antes que las sentencias 4, 6, 7 y 9, que dependen de ella.
CREATE OR REPLACE VIEW growth_funnel.v_monthly_transactions AS
SELECT
    date_format(date_trunc('month', event_timestamp), '%Y-%m') AS month,
    user_id,
    amount,
    is_fraud
FROM growth_funnel.product_events_parquet
WHERE event_name IN ('first_transaction', 'repeat_transaction');

-- ===== SENTENCIA 4: TPV mensual (métrica 3) y ticket promedio (métrica 4) =====
SELECT
    month,
    ROUND(SUM(amount), 2) AS tpv_pen,
    COUNT(*)              AS n_transacciones,
    ROUND(AVG(amount), 2) AS ticket_promedio_pen
FROM growth_funnel.v_monthly_transactions
GROUP BY month
ORDER BY month;

-- ===== SENTENCIA 5: ARPU mensual (métrica 5) = TPV del mes / usuarios activos del mes =====
WITH monthly_tpv AS (
    SELECT month, SUM(amount) AS tpv_pen, COUNT(DISTINCT user_id) AS usuarios_activos
    FROM growth_funnel.v_monthly_transactions
    GROUP BY month
)
SELECT
    month,
    tpv_pen,
    usuarios_activos,
    ROUND(tpv_pen / NULLIF(usuarios_activos, 0), 2) AS arpu_pen
FROM monthly_tpv
ORDER BY month;

-- ===== SENTENCIA 6: LTV simplificado (métrica 6) = ARPU promedio x retención promedio en meses =====
-- NOTA METODOLÓGICA: esta es una aproximación simplificada, NO un LTV de
-- cohorte madura, porque la ventana de datos sintéticos es de solo 6
-- meses. Un LTV robusto requeriría observar cohortes completas durante
-- 12-24+ meses y modelar la curva de decaimiento de retención.
WITH monthly_tpv AS (
    SELECT month, SUM(amount) AS tpv_pen, COUNT(DISTINCT user_id) AS usuarios_activos
    FROM growth_funnel.v_monthly_transactions
    GROUP BY month
),
arpu AS (
    SELECT AVG(tpv_pen / NULLIF(usuarios_activos, 0)) AS arpu_promedio_pen
    FROM monthly_tpv
),
retention_months AS (
    -- Meses distintos con al menos una transacción, por usuario activado
    SELECT
        user_id,
        COUNT(DISTINCT date_trunc('month', event_timestamp)) AS meses_activos
    FROM growth_funnel.product_events_parquet
    WHERE event_name IN ('first_transaction', 'repeat_transaction')
    GROUP BY user_id
),
avg_retention AS (
    SELECT AVG(meses_activos) AS retencion_promedio_meses
    FROM retention_months
)
SELECT
    ROUND(a.arpu_promedio_pen, 2)                                  AS arpu_promedio_pen,
    ROUND(r.retencion_promedio_meses, 2)                           AS retencion_promedio_meses,
    ROUND(a.arpu_promedio_pen * r.retencion_promedio_meses, 2)     AS ltv_simplificado_pen,
    'Aproximacion: ventana de datos de 6 meses, no cohorte madura' AS nota_metodologica
FROM arpu a
CROSS JOIN avg_retention r;

-- ===== SENTENCIA 7: LTV:CAC por canal (métrica 7) =====
-- Usa el mismo LTV simplificado agregado (sentencia 6) comparado contra el
-- CAC promedio de cada canal en el periodo.
WITH monthly_tpv AS (
    SELECT month, SUM(amount) AS tpv_pen, COUNT(DISTINCT user_id) AS usuarios_activos
    FROM growth_funnel.v_monthly_transactions
    GROUP BY month
),
arpu AS (
    SELECT AVG(tpv_pen / NULLIF(usuarios_activos, 0)) AS arpu_promedio_pen
    FROM monthly_tpv
),
retention_months AS (
    SELECT user_id, COUNT(DISTINCT date_trunc('month', event_timestamp)) AS meses_activos
    FROM growth_funnel.product_events_parquet
    WHERE event_name IN ('first_transaction', 'repeat_transaction')
    GROUP BY user_id
),
avg_retention AS (
    SELECT AVG(meses_activos) AS retencion_promedio_meses FROM retention_months
),
ltv AS (
    SELECT a.arpu_promedio_pen * r.retencion_promedio_meses AS ltv_simplificado_pen
    FROM arpu a CROSS JOIN avg_retention r
),
new_users AS (
    SELECT
        channel,
        date_format(date_trunc('month', event_timestamp), '%Y-%m') AS month,
        COUNT(DISTINCT user_id) AS nuevos_usuarios
    FROM growth_funnel.product_events_parquet
    WHERE event_name = 'signup'
    GROUP BY channel, date_trunc('month', event_timestamp)
),
cac_por_canal AS (
    SELECT
        nu.channel,
        SUM(CAST(ac.acquisition_cost_pen AS DOUBLE)) / NULLIF(SUM(nu.nuevos_usuarios), 0) AS cac_promedio_pen
    FROM new_users nu
    JOIN growth_funnel.raw_acquisition_costs ac
        ON ac.channel = nu.channel AND ac.month = nu.month
    GROUP BY nu.channel
)
SELECT
    c.channel,
    ROUND(c.cac_promedio_pen, 2)                                     AS cac_promedio_pen,
    ROUND(l.ltv_simplificado_pen, 2)                                 AS ltv_simplificado_pen,
    ROUND(l.ltv_simplificado_pen / NULLIF(c.cac_promedio_pen, 0), 2) AS ratio_ltv_cac
FROM cac_por_canal c
CROSS JOIN ltv l
ORDER BY ratio_ltv_cac DESC;

-- ===== SENTENCIA 8: tasa de fraude mensual (métrica 8) =====
-- is_fraud ya es BOOLEAN en product_events_parquet (y por lo tanto en la
-- vista v_monthly_transactions, que se define sobre esa tabla) — se usa
-- directo en la condición CASE WHEN is_fraud, sin CAST.
SELECT
    month,
    COUNT(*)                                                    AS total_transacciones,
    SUM(CASE WHEN is_fraud THEN 1 ELSE 0 END)                   AS transacciones_fraude,
    ROUND(100.0 * SUM(CASE WHEN is_fraud THEN 1 ELSE 0 END) / COUNT(*), 3) AS tasa_fraude_pct
FROM growth_funnel.v_monthly_transactions
GROUP BY month
ORDER BY month;
