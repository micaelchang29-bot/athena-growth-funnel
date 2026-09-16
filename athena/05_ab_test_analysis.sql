-- =============================================================================
-- 05_ab_test_analysis.sql
-- Tasa de conversión por variante del test A/B (dato sintético).
-- La significancia estadística (z-test de proporciones) se calcula en
-- scripts/ab_test_significance.py, ya que Athena SQL no tiene funciones
-- estadísticas nativas para eso.
--
-- NOTA: raw_ab_test.converted se declaró como STRING en la tabla externa
-- (OpenCSVSerde lee todas las columnas como string), por eso se castea a
-- INTEGER aquí antes de sumarlo.
-- =============================================================================

SELECT
    variant,
    COUNT(*)                                                  AS usuarios,
    SUM(CAST(converted AS INTEGER))                           AS conversiones,
    ROUND(100.0 * SUM(CAST(converted AS INTEGER)) / COUNT(*), 2) AS tasa_conversion_pct
FROM growth_funnel.raw_ab_test
GROUP BY variant
ORDER BY variant;

-- Diferencia absoluta de tasas de conversión (test - control), para llevar
-- a exports/ab_test_result.csv junto con el resultado de significancia.
WITH rates AS (
    SELECT
        variant,
        SUM(CAST(converted AS INTEGER)) * 1.0 / COUNT(*) AS conversion_rate,
        COUNT(*) AS n
    FROM growth_funnel.raw_ab_test
    GROUP BY variant
)
SELECT
    MAX(CASE WHEN variant = 'control' THEN conversion_rate END) AS tasa_control,
    MAX(CASE WHEN variant = 'test' THEN conversion_rate END)    AS tasa_test,
    MAX(CASE WHEN variant = 'test' THEN conversion_rate END)
        - MAX(CASE WHEN variant = 'control' THEN conversion_rate END) AS diferencia_absoluta,
    MAX(CASE WHEN variant = 'control' THEN n END) AS n_control,
    MAX(CASE WHEN variant = 'test' THEN n END)    AS n_test
FROM rates;
