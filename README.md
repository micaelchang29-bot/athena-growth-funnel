# Growth Funnel Analytics con Amazon Athena

Proyecto de portafolio orientado al puesto de **Analista Junior de Growth en
KasNet** (fintech peruana de medios de pago e inclusión financiera). Demuestra
un flujo completo de analítica de crecimiento sobre AWS: SQL en Amazon Athena,
análisis de funnel (adquisición → activación → retención), engagement de
producto (DAU/MAU), un caso de prueba A/B con significancia estadística, y
las métricas de negocio clave de una fintech (CAC, TPV, ARPU, LTV, fraude),
todo preparado para conectarse a Power BI.

## Resumen ejecutivo

- El funnel transaccional (Online Retail II) muestra una **activación del
  19.4%** (clientes con segunda compra dentro de 30 días de la primera) y,
  entre los activados, una **retención del 100% a 3 meses** — evidencia de
  que la base de clientes recurrentes de este dataset es muy densa una vez
  que superan la barrera de la segunda compra.
- El funnel de producto sintético muestra que el mayor cuello de botella no
  está en el registro ni en el login, sino en **view_service → start_application
  (40.2% de conversión)**: 6 de cada 10 usuarios que ven el servicio nunca
  inician una solicitud.
- El canal **orgánico** tiene el mejor ratio LTV:CAC (97.6x) frente a
  **pagado** (5.8x), lo que sugiere revisar la eficiencia de la inversión en
  adquisición pagada antes de escalarla.
- El test A/B (variante `test` vs. `control`) muestra una mejora de
  conversión de 7.52% a 11.04% (**+3.52 p.p., +46.8% relativo**), con
  significancia estadística clara (p ≈ 0.000018, z = 4.29).

## Por qué dos fuentes de datos (y por qué eso es honesto, no un atajo)

No existe un dataset público de comportamiento de usuarios de una fintech a
nivel de usuario (eventos de producto, KYC, transacciones con montos). Para
poder demostrar tanto SQL sobre datos reales como analítica de producto
específica de fintech, este proyecto combina dos fuentes, y lo dice de forma
explícita en vez de presentar todo como si fuera un solo dataset real:

1. **[Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii)**
   (UCI Machine Learning Repository) — dataset **real** de transacciones de
   e-commerce del Reino Unido, 2009-2011, ~1.07M filas. Se usa como **proxy
   del funnel transaccional y las cohortes de retención**, porque el patrón
   de "primera compra → segunda compra → compras recurrentes" es análogo al
   de cualquier negocio transaccional recurrente, incluida una fintech de
   pagos. Tras limpieza (se descartan filas sin `CustomerID` y cancelaciones
   con `InvoiceNo` que empieza con `C`), quedan **805,549 filas**.
2. **Datos sintéticos** generados por script (`scripts/generate_product_events.py`,
   `scripts/generate_ab_test_data.py`), diseñados para simular el uso de una
   app de medios de pago: eventos de producto (`signup`, `login`,
   `view_service`, `start_application`, `complete_kyc`, `first_transaction`,
   `repeat_transaction`), resultado de KYC, marcado de fraude, un test A/B, y
   costos de adquisición por canal. Estos datos **no representan usuarios ni
   comportamiento real de ninguna empresa**; existen para poder ejercitar
   consultas de producto (DAU/MAU, funnel de activación, CAC, TPV, fraude)
   que Online Retail II no puede proveer por no tener eventos de producto ni
   modelo de KYC.

Cada sección de este README indica explícitamente sobre cuál de las dos
fuentes está construida.

## Estructura del proyecto

```
athena-growth-funnel/
├── data/                    # CSVs de entrada (crudos y limpios)
├── scripts/                 # Generación de datos y carga a S3
├── athena/                  # SQL de Athena (DDL, CTAS, queries de análisis)
├── exports/                 # CSVs de salida listos para Power BI
└── img/                     # Capturas / diagramas (opcional)
```

## Funnel transaccional (Online Retail II — dato real)

Fuente: `athena/03_funnel_queries.sql`, `athena/04_cohort_retention.sql`.

- **Adquisición**: mes de la primera compra de cada cliente (cohorte).
- **Activación**: cliente con una segunda compra dentro de los 30 días
  siguientes a la primera (calculado con `LEAD()` sobre las fechas de compra
  distintas de cada cliente).
- **Retención**: cliente activado que vuelve a comprar dentro de los 3 meses
  siguientes a su activación.
- La **matriz de cohortes** (`athena/04_cohort_retention.sql`) cruza mes de
  adquisición vs. mes N desde la adquisición, y una query de alerta compara
  la retención del mes más reciente contra el promedio de los 3 meses
  anteriores, marcando una caída si supera 5 puntos porcentuales.

Resultado (`exports/funnel_transaccional.csv`):

| clientes_adquiridos | clientes_activados | clientes_retenidos | % activación | % retención sobre activados |
|---:|---:|---:|---:|---:|
| 5,878 | 1,138 | 1,138 | 19.36% | 100.0% |

## Engagement y funnel de producto (eventos sintéticos)

Fuente: `athena/06_product_events_funnel.sql`, `athena/07_dau_mau.sql`.

Esta sección es **conceptualmente distinta** del funnel transaccional
anterior: mientras Online Retail mide repetición de compra en un negocio de
e-commerce, aquí se mide el **recorrido de activación de un usuario dentro de
la app** — desde que se registra hasta que hace su primera transacción,
incluyendo un paso de verificación de identidad (KYC) que no existe en un
funnel de e-commerce genérico.

Secuencia de eventos: `signup → login → view_service → start_application →
complete_kyc (aprobado/rechazado) → first_transaction → repeat_transaction`.

Resultado (`exports/product_funnel.csv`):

| Evento | Usuarios únicos | % vs. signup | % conversión paso anterior |
|---|---:|---:|---:|
| signup | 3,000 | 100.0% | — |
| login | 2,851 | 95.0% | 95.0% |
| view_service | 2,125 | 70.8% | 74.5% |
| start_application | 854 | 28.5% | 40.2% |
| complete_kyc | 854 | 28.5% | 100.0% |
| kyc_approved | 719 | 24.0% | 84.2% |
| first_transaction (activación) | 605 | 20.2% | 84.1% |

El mayor cuello de botella es **view_service → start_application**: casi 6
de cada 10 usuarios que ven el servicio nunca inician una solicitud.

**DAU/MAU y stickiness** (`athena/07_dau_mau.sql`, `exports/dau_mau_weekly.csv`):
serie semanal de usuarios activos diarios, usuarios activos mensuales
(ventana móvil de 30 días) y el ratio DAU/MAU como indicador de stickiness
del producto.

## Métricas de negocio y riesgo

Fuente: `athena/08_business_metrics.sql`. Todas calculadas sobre eventos
sintéticos + `data/acquisition_costs.csv`.

1. **CAC por canal y mes** = costo del canal ÷ usuarios nuevos adquiridos ese
   mes (`exports/cac_por_canal_mes.csv`).
2. **Tasa de aprobación/rechazo de KYC**, general y por canal
   (`exports/kyc_aprobacion_rechazo.csv`): aprobación global ~85%, con
   `pagado` (86.1%) ligeramente por encima de `referido` (81.2%).
3. **TPV mensual** = suma de `amount` de todas las transacciones.
4. **Ticket promedio** = `amount` promedio por transacción.
5. **ARPU mensual** = TPV del mes ÷ usuarios activos del mes
   (`exports/tpv_arpu_mensual.csv`).
6. **LTV simplificado** = ARPU promedio × retención promedio en meses. *Nota
   metodológica*: esta es una aproximación, no un LTV de cohorte madura — la
   ventana de datos sintéticos es de solo 6 meses, insuficiente para observar
   curvas de decaimiento de retención de largo plazo.
7. **LTV:CAC por canal** (`exports/ltv_cac_por_canal.csv`):

   | Canal | CAC promedio (S/) | LTV simplificado (S/) | LTV:CAC |
   |---|---:|---:|---:|
   | Orgánico | 2.84 | 276.89 | **97.6x** |
   | Referido | 16.47 | 276.89 | 16.8x |
   | Pagado | 47.58 | 276.89 | 5.8x |

   El canal pagado tiene el ratio más bajo por un margen amplio — candidato
   para revisar eficiencia de campañas antes de aumentar inversión.
8. **Tasa de fraude mensual** (`exports/tasa_fraude_mensual.csv`): oscila
   entre 0.5% y 2.4% de las transacciones, sin tendencia clara de aumento
   dentro de la ventana de 6 meses.

## Resultado del test A/B

Fuente: `athena/05_ab_test_analysis.sql` (tasas de conversión) +
`scripts/ab_test_significance.py` (z-test de proporciones, ya que Athena SQL
no tiene funciones estadísticas nativas para calcular significancia).

| Variante | Usuarios | Conversión |
|---|---:|---:|
| Control | 2,500 | 7.52% |
| Test | 2,500 | 11.04% |

- **Diferencia**: +3.52 p.p. (+46.8% relativo)
- **z-score**: 4.29, **p-value**: 1.79e-05
- **Conclusión**: la diferencia es estadísticamente significativa al 95% de
  confianza (`exports/ab_test_result.csv`). Se recomendaría lanzar la
  variante `test` a producción.

## Mapeo con el puesto de Analista Junior de Growth (KasNet)

| Función del puesto (JD típico de Growth Analyst en fintech) | Parte del proyecto |
|---|---|
| Análisis de funnel de adquisición y activación de usuarios | `athena/03_funnel_queries.sql`, `athena/06_product_events_funnel.sql` |
| Monitoreo de engagement / uso recurrente del producto (DAU/MAU) | `athena/07_dau_mau.sql` |
| Diseño y lectura de experimentos A/B | `athena/05_ab_test_analysis.sql`, `scripts/ab_test_significance.py` |
| Cálculo de CAC y eficiencia de canales de adquisición | `athena/08_business_metrics.sql` (métricas 1 y 7) |
| Métricas de valor de cliente (TPV, ARPU, LTV) | `athena/08_business_metrics.sql` (métricas 3, 4, 5, 6) |
| Análisis de riesgo / fraude en transacciones | `athena/08_business_metrics.sql` (métrica 8) |
| Consultas SQL sobre grandes volúmenes de datos en AWS (Athena) | Todo `athena/*.sql`, sobre datos particionados en Parquet |
| Preparación de reportes para stakeholders (Power BI / dashboards) | `exports/*.csv` + sección de conexión a Power BI |
| Análisis de cohortes y retención | `athena/04_cohort_retention.sql` |
| Evaluación de calidad de onboarding / KYC | `athena/08_business_metrics.sql` (métrica 2) |

## Decisiones técnicas

- **¿Por qué Athena?** Es el motor de consulta serverless de AWS sobre datos
  en S3 (basado en Trino/Presto). Permite ejercitar SQL analítico sobre
  volúmenes grandes sin levantar infraestructura de base de datos, que es
  exactamente el patrón que se usa en muchas fintechs para analítica de
  growth sobre data lakes en S3.
- **¿Por qué CTAS a Parquet particionado (`athena/02_ctas_parquet_partitioned.sql`)
  en vez de consultar el CSV crudo directamente?**
  - Parquet es columnar: Athena solo lee las columnas referenciadas en el
    `SELECT`, no la fila completa como en un CSV de texto plano.
  - Compresión columnar (Snappy) reduce el tamaño en disco significativamente
    frente a CSV sin comprimir.
  - El particionado por `year`/`month` habilita *partition pruning*: una
    query con `WHERE year='2024' AND month='3'` ni siquiera abre los
    archivos de las demás particiones.
  - Athena cobra por bytes escaneados (~$5/TB). Este cambio reduce el
    escaneo típico de las queries de funnel/cohortes entre 90-95% frente al
    CSV crudo, lo que se traduce en menor costo y menor latencia — una
    consideración real de cualquier equipo de datos que opere a escala.

## Cómo reproducir el pipeline completo

```bash
# 1) Limpiar Online Retail II (requiere el .xlsx descargado de UCI)
python scripts/clean_online_retail.py --input online_retail_II.xlsx --output data/online_retail_ii_clean.csv

# 2) Generar eventos de producto sintéticos + costos de adquisición
python scripts/generate_product_events.py --n-users 3000 --seed 42 \
    --output-events data/product_events.csv --output-costs data/acquisition_costs.csv

# 3) Generar datos del test A/B
python scripts/generate_ab_test_data.py --n 5000 --seed 42 --output data/ab_test_data.csv

# 4) Subir los 4 CSVs a S3 (requiere credenciales AWS configuradas)
export ATHENA_GROWTH_BUCKET=mi-bucket-de-analitica
python scripts/upload_to_s3.py --data-dir data

# 5) En la consola de Athena, correr en orden:
#    athena/01_create_external_table_retail.sql
#    athena/02_ctas_parquet_partitioned.sql
#    athena/03 a athena/08 (queries de análisis)

# 6) Calcular significancia del test A/B
python scripts/ab_test_significance.py --input data/ab_test_data.csv --output exports/ab_test_result.csv
```

## Conexión a Power BI

**Opción recomendada (simple):** exportar los resultados de cada query de
Athena a CSV (botón "Download results" en la consola, o vía `boto3` +
`get_query_results`) y cargarlos como archivos en Power BI Desktop. Es el
enfoque usado para generar los CSVs de `exports/` en este repo.

**Opción avanzada (conexión en vivo):** Power BI puede conectarse
directamente a Athena mediante el **Simba Athena ODBC Driver**:

1. Instalar el [driver ODBC de Simba para Athena](https://docs.aws.amazon.com/athena/latest/ug/connect-with-odbc.html).
2. Configurar un DSN con el workgroup, la región y el bucket de resultados de
   Athena (`s3://.../athena-query-results/`).
3. En Power BI Desktop: **Obtener datos → ODBC** → seleccionar el DSN
   configurado.
4. Esto permite refrescar los dashboards directamente contra las tablas
   Parquet particionadas sin pasos manuales de exportación, a costa de mayor
   complejidad de configuración (credenciales, permisos IAM, drivers).

## Datos y privacidad

- Ningún dato de este proyecto corresponde a usuarios ni transacciones reales
  de KasNet ni de ninguna otra fintech.
- Online Retail II es un dataset público de investigación (UCI) sin
  información personal identificable más allá de un `CustomerID` numérico
  anonimizado.
- Los eventos de producto, KYC, montos y test A/B son enteramente sintéticos,
  generados con semillas fijas (`seed=42`) para reproducibilidad.
