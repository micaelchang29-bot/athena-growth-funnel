-- =============================================================================
-- 06_product_events_funnel.sql
-- Funnel de producto sobre eventos sintéticos (activación), distinto del
-- funnel transaccional de Online Retail: aquí se mide el recorrido completo
-- signup -> login -> view_service -> start_application -> complete_kyc ->
-- first_transaction, incluyendo el resultado del KYC.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Usuarios únicos por evento de la secuencia + % de conversión entre
--    pares consecutivos
-- -----------------------------------------------------------------------------
WITH event_counts AS (
    SELECT event_name, COUNT(DISTINCT user_id) AS usuarios_unicos
    FROM growth_funnel.product_events_parquet
    WHERE event_name IN ('signup', 'login', 'view_service', 'start_application', 'complete_kyc')
    GROUP BY event_name

    UNION ALL

    -- complete_kyc con resultado aprobado se trata como el paso real hacia
    -- first_transaction (solo los aprobados pueden transaccionar)
    SELECT 'kyc_approved' AS event_name, COUNT(DISTINCT user_id) AS usuarios_unicos
    FROM growth_funnel.product_events_parquet
    WHERE event_name = 'complete_kyc' AND kyc_result = 'kyc_approved'

    UNION ALL

    SELECT event_name, COUNT(DISTINCT user_id) AS usuarios_unicos
    FROM growth_funnel.product_events_parquet
    WHERE event_name = 'first_transaction'
    GROUP BY event_name
),
ordered AS (
    SELECT
        event_name,
        usuarios_unicos,
        CASE event_name
            WHEN 'signup'             THEN 1
            WHEN 'login'              THEN 2
            WHEN 'view_service'       THEN 3
            WHEN 'start_application'  THEN 4
            WHEN 'complete_kyc'       THEN 5
            WHEN 'kyc_approved'       THEN 6
            WHEN 'first_transaction'  THEN 7
        END AS step_order
    FROM event_counts
)
SELECT
    step_order,
    event_name,
    usuarios_unicos,
    ROUND(100.0 * usuarios_unicos / FIRST_VALUE(usuarios_unicos) OVER (ORDER BY step_order), 2) AS pct_sobre_signup,
    ROUND(100.0 * usuarios_unicos / LAG(usuarios_unicos) OVER (ORDER BY step_order), 2)          AS pct_conversion_paso_anterior
FROM ordered
ORDER BY step_order;

-- -----------------------------------------------------------------------------
-- 2) Tiempo promedio entre cada par de eventos consecutivos (en horas)
-- -----------------------------------------------------------------------------
WITH per_user_events AS (
    SELECT
        user_id,
        event_name,
        MIN(event_timestamp) AS event_timestamp
    FROM growth_funnel.product_events_parquet
    WHERE event_name IN ('signup', 'login', 'view_service', 'start_application', 'complete_kyc', 'first_transaction')
    GROUP BY user_id, event_name
),
pivoted AS (
    SELECT
        user_id,
        MAX(CASE WHEN event_name = 'signup' THEN event_timestamp END)            AS ts_signup,
        MAX(CASE WHEN event_name = 'login' THEN event_timestamp END)             AS ts_login,
        MAX(CASE WHEN event_name = 'view_service' THEN event_timestamp END)      AS ts_view_service,
        MAX(CASE WHEN event_name = 'start_application' THEN event_timestamp END) AS ts_start_application,
        MAX(CASE WHEN event_name = 'complete_kyc' THEN event_timestamp END)      AS ts_complete_kyc,
        MAX(CASE WHEN event_name = 'first_transaction' THEN event_timestamp END) AS ts_first_transaction
    FROM per_user_events
    GROUP BY user_id
)
SELECT
    ROUND(AVG(date_diff('minute', ts_signup, ts_login)) / 60.0, 2)                AS horas_signup_a_login,
    ROUND(AVG(date_diff('minute', ts_login, ts_view_service)) / 60.0, 2)          AS horas_login_a_view_service,
    ROUND(AVG(date_diff('minute', ts_view_service, ts_start_application)) / 60.0, 2) AS horas_view_service_a_start_application,
    ROUND(AVG(date_diff('minute', ts_start_application, ts_complete_kyc)) / 60.0, 2) AS horas_start_application_a_complete_kyc,
    ROUND(AVG(date_diff('minute', ts_complete_kyc, ts_first_transaction)) / 60.0, 2)  AS horas_complete_kyc_a_first_transaction
FROM pivoted;
