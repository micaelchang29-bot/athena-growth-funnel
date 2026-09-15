-- =============================================================================
-- 07_dau_mau.sql
-- DAU, MAU (ventana móvil de 30 días) y stickiness (DAU/MAU) semanal, sobre
-- eventos sintéticos de producto.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- DAU: usuarios únicos con al menos un evento por día
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW growth_funnel.v_dau AS
SELECT
    date_trunc('day', event_timestamp) AS activity_day,
    COUNT(DISTINCT user_id)            AS dau
FROM growth_funnel.product_events_parquet
GROUP BY date_trunc('day', event_timestamp);

-- -----------------------------------------------------------------------------
-- MAU: usuarios únicos con evento en los últimos 30 días (ventana móvil,
-- una fila por día calendario dentro del rango de datos)
-- -----------------------------------------------------------------------------
WITH days AS (
    SELECT DISTINCT date_trunc('day', event_timestamp) AS activity_day
    FROM growth_funnel.product_events_parquet
),
mau_per_day AS (
    SELECT
        d.activity_day,
        COUNT(DISTINCT pe.user_id) AS mau
    FROM days d
    JOIN growth_funnel.product_events_parquet pe
        ON pe.event_timestamp > d.activity_day - INTERVAL '30' DAY
       AND pe.event_timestamp <= d.activity_day
    GROUP BY d.activity_day
)
SELECT activity_day, mau
FROM mau_per_day
ORDER BY activity_day;

-- -----------------------------------------------------------------------------
-- Stickiness (DAU/MAU) por semana, como serie de tiempo
-- -----------------------------------------------------------------------------
WITH days AS (
    SELECT DISTINCT date_trunc('day', event_timestamp) AS activity_day
    FROM growth_funnel.product_events_parquet
),
dau_daily AS (
    SELECT
        date_trunc('day', event_timestamp) AS activity_day,
        COUNT(DISTINCT user_id)            AS dau
    FROM growth_funnel.product_events_parquet
    GROUP BY date_trunc('day', event_timestamp)
),
mau_daily AS (
    SELECT
        d.activity_day,
        COUNT(DISTINCT pe.user_id) AS mau
    FROM days d
    JOIN growth_funnel.product_events_parquet pe
        ON pe.event_timestamp > d.activity_day - INTERVAL '30' DAY
       AND pe.event_timestamp <= d.activity_day
    GROUP BY d.activity_day
),
daily_stickiness AS (
    SELECT
        dd.activity_day,
        date_trunc('week', dd.activity_day) AS activity_week,
        dd.dau,
        md.mau,
        CAST(dd.dau AS DOUBLE) / NULLIF(md.mau, 0) AS stickiness
    FROM dau_daily dd
    JOIN mau_daily md ON md.activity_day = dd.activity_day
)
SELECT
    activity_week,
    ROUND(AVG(dau), 1)         AS dau_promedio_semana,
    ROUND(AVG(mau), 1)         AS mau_promedio_semana,
    ROUND(AVG(stickiness) * 100, 2) AS stickiness_pct_promedio
FROM daily_stickiness
GROUP BY activity_week
ORDER BY activity_week;
