# Growth Funnel Analytics con Amazon Athena

Proyecto de portafolio que demuestra un flujo completo de analítica de
crecimiento (growth analytics) sobre AWS: SQL en Amazon Athena, análisis de
funnel (adquisición → activación → retención), cohortes de retención,
engagement de producto (DAU/MAU), un caso de prueba A/B con significancia
estadística, y las métricas de negocio clave de un producto transaccional
(CAC, TPV, ARPU, LTV, tasa de fraude), con resultados exportados y listos
para conectarse a Power BI.

Todas las cifras de este README provienen de las queries reales ejecutadas
en Athena (no de una simulación local) — los CSVs de resultados están en
`exports/`.

## Resumen ejecutivo

- **Funnel transaccional real (Online Retail II)**: de 5,878 clientes
  adquiridos, el 19.36% se activa (segunda compra dentro de 30 días), y de
  esos activados, el **58.52% se retiene** (vuelve a comprar en los 3 meses
  siguientes a su activación). La matriz de cohortes muestra una **caída de
  retención de -14.68 p.p. en la cohorte más reciente** (nov-2011: 14.14%
  vs. 28.82% de promedio de las 3 cohortes previas) — señal de alerta que
  ameritaría investigación en un contexto real.
- **Funnel de producto sintético**: el mayor cuello de botella no está en
  el registro ni en el login (95.0% de conversión), sino en
  **view_service → start_application (40.2%)**: 6 de cada 10 usuarios que
  ven el servicio nunca inician una solicitud. El tiempo promedio más largo
  entre etapas es **start_application → complete_kyc (48.3 horas)**.
- **Test A/B con resultado estadísticamente significativo**: la variante
  `test` convierte a 11.04% (276/2500) vs. 7.52% (188/2500) de `control`
  (+3.52 p.p., +46.8% relativo). z-score = 4.29, p-value = 1.79e-05 — muy
  por debajo del umbral de 0.05, por lo que se recomendaría lanzar la
  variante `test`.
- **Eficiencia de canales muy dispar**: el canal orgánico tiene un ratio
  LTV:CAC de **97.6x**, frente a apenas **5.8x** del canal pagado — el CAC
  promedio pagado (S/ 47.58) es casi 17 veces el orgánico (S/ 2.84). La tasa
  de fraude mensual se mantiene acotada entre 0.5% y 2.35%, sin tendencia
  clara de crecimiento en la ventana de 6 meses observada.

## Por qué dos fuentes de datos (y por qué eso es honesto, no un atajo)

No existe un dataset público de comportamiento de usuarios de una fintech o
app de pagos a nivel de usuario (eventos de producto, verificación de
identidad/KYC, transacciones con montos). Para poder demostrar tanto SQL
sobre datos reales como analítica de producto específica de un negocio
transaccional, este proyecto combina dos fuentes y lo declara de forma
explícita en vez de presentar todo como si fuera un solo dataset real:

1. **[Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii)**
   (UCI Machine Learning Repository) — dataset **real** de transacciones de
   e-commerce del Reino Unido, 2009-2011, ~1.07M filas. Se usa como **proxy
   del funnel transaccional y las cohortes de retención**, porque el patrón
   "primera compra → segunda compra → compras recurrentes" es análogo al de
   cualquier negocio transaccional recurrente. Tras limpieza (se descartan
   filas sin `CustomerID` y cancelaciones con `InvoiceNo` que empieza con
   `C`), quedan **805,549 filas**.
2. **Datos sintéticos** generados por script (`scripts/generate_product_events.py`,
   `scripts/generate_ab_test_data.py`), diseñados para simular el uso de una
   app de pagos: eventos de producto (`signup`, `login`, `view_service`,
   `start_application`, `complete_kyc`, `first_transaction`,
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
├── scripts/                 # Generación de datos, carga a S3, significancia A/B
├── athena/                  # SQL de Athena (DDL, CTAS, queries de análisis)
├── exports/                 # CSVs de salida reales de Athena, listos para Power BI
├── dashboard/               # Dashboard de Power BI (growth-funnel-dashboard.pbix)
└── img/                     # Capturas / diagramas (opcional)
```

## Funnel transaccional (Online Retail II — dato real)

Fuente: `athena/03_funnel_queries.sql`, `athena/04_cohort_retention.sql`.

- **Adquisición**: mes de la primera compra de cada cliente (cohorte).
- **Activación**: cliente con una segunda compra dentro de los 30 días
  siguientes a la primera (calculado con `LEAD()` sobre las fechas de compra
  distintas de cada cliente).
- **Retención**: cliente activado que vuelve a comprar dentro de los 3 meses
  siguientes a su activación, **excluyendo explícitamente la compra que ya
  definió la activación** (ver sección de debugging más abajo — este es un
  detalle importante que causó un bug real durante el desarrollo).

Resultado (`exports/03_funnel_transaccional_adquisicion_activacion_retencion.csv`):

| clientes_adquiridos | clientes_activados | clientes_retenidos | % activación | % retención sobre activados |
|---:|---:|---:|---:|---:|
| 5,878 | 1,138 | 666 | 19.36% | 58.52% |

**Matriz de cohortes** (`exports/04_matriz_cohortes_retencion_mensual.csv`,
326 filas): cruza mes de adquisición vs. mes N desde la adquisición. Por
ejemplo, la cohorte de diciembre 2009 retiene 35.29% en el mes 1 y se
estabiliza entre 30-40% en los meses siguientes — un patrón típico de
negocio con base de clientes recurrente pero con caída fuerte tras la
primera compra.

**Alerta de retención** (`exports/04b_alerta_caida_retencion_ultimo_mes.csv`):
la query compara la retención a 1 mes de la cohorte más reciente contra el
promedio de las 3 cohortes anteriores, marcando una alerta si la caída
supera 5 puntos porcentuales:

| Mes más reciente | Retención mes N=1 | Promedio 3 meses previos | Diferencia | Estado |
|---|---:|---:|---:|---|
| 2011-11 | 14.14% | 28.82% | -14.68 p.p. | **ALERTA: caída > 5pp** |

## Engagement y funnel de producto (eventos sintéticos)

Fuente: `athena/06_product_events_funnel.sql`, `athena/07_dau_mau.sql`.

Esta sección es **conceptualmente distinta** del funnel transaccional
anterior: mientras Online Retail mide repetición de compra en un negocio de
e-commerce, aquí se mide el **recorrido de activación de un usuario dentro de
la app** — desde que se registra hasta que hace su primera transacción,
incluyendo un paso de verificación de identidad (KYC) que no existe en un
funnel de e-commerce genérico.

Secuencia: `signup → login → view_service → start_application →
complete_kyc (aprobado/rechazado) → first_transaction → repeat_transaction`.

Resultado (`exports/06a_funnel_producto_conteo_conversion_por_etapa.csv`):

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

**Tiempo promedio entre etapas** (`exports/06b_funnel_producto_tiempo_promedio_entre_etapas.csv`,
en horas):

| Transición | Horas promedio |
|---|---:|
| signup → login | 23.81 |
| login → view_service | 11.89 |
| view_service → start_application | 36.08 |
| start_application → complete_kyc | **48.26** |
| complete_kyc → first_transaction | 24.70 |

El paso más lento es completar el KYC una vez iniciada la solicitud (~2
días), lo que sumado a su baja conversión (40.2% antes de este paso) lo
convierte en el punto de fricción más crítico del funnel.

**DAU/MAU y stickiness** (`exports/07a_mau_ventana_movil_diaria.csv`,
`exports/07b_dau_mau_stickiness_semanal.csv`): serie de usuarios activos
diarios/mensuales (ventana móvil de 30 días) y el ratio DAU/MAU semanal
como indicador de stickiness. *Nota de calidad de datos*: en las primeras
semanas de la ventana de 6 meses, el stickiness calculado supera 100%
(ej. semana del 2024-01-01: DAU promedio 68.8, MAU promedio 99.8,
stickiness 105.4%). Esto es un artefacto esperado de la ventana móvil de 30
días aplicada a datos que recién empiezan: al no haber todavía 30 días de
historial acumulado, el denominador (MAU) se subestima. El indicador se
vuelve confiable a partir de la cuarta semana en adelante.

## Métricas de negocio y riesgo

Fuente: `athena/08_business_metrics.sql`. Todas calculadas sobre eventos
sintéticos + `data/acquisition_costs.csv`.

**1) CAC por canal y mes** (`exports/08a_cac_por_canal_mes.csv`): el canal
pagado cuesta consistentemente entre S/ 42-52 por usuario nuevo, frente a
S/ 2.6-3.6 del orgánico y S/ 15-18 del referido.

**2) Aprobación/rechazo de KYC** (`exports/08b_tasa_aprobacion_rechazo_kyc.csv`):
aprobación global de 84.19%, con `pagado` (86.1%) ligeramente por encima de
`referido` (81.2%) y `orgánico` (83.71%).

**3-4) TPV mensual y ticket promedio** (`exports/08c_tpv_mensual_ticket_promedio.csv`):
el TPV crece de S/ 15,292 (enero) a un pico de S/ 53,455 (marzo), luego cae
— consistente con que los usuarios de los últimos meses de la ventana aún no
alcanzan a generar transacciones repetidas dentro del periodo observado. El
ticket promedio se mantiene estable entre S/ 45-54.

**5) ARPU mensual** (`exports/08d_arpu_mensual.csv`): crece de S/ 98.03 en
enero a S/ 180.11 en abril, reflejando que los usuarios más antiguos
concentran más transacciones repetidas conforme pasa el tiempo.

**6) LTV simplificado** (`exports/08e_ltv_simplificado.csv`) = ARPU
promedio (S/ 144.29) × retención promedio (1.92 meses) = **S/ 276.89**.
*Nota metodológica*: esta es una aproximación, no un LTV de cohorte madura
— la ventana de datos sintéticos es de solo 6 meses, insuficiente para
observar curvas de decaimiento de retención de largo plazo.

**7) LTV:CAC por canal** (`exports/08f_ltv_cac_por_canal.csv`):

| Canal | CAC promedio (S/) | LTV simplificado (S/) | LTV:CAC |
|---|---:|---:|---:|
| Orgánico | 2.84 | 276.89 | **97.6x** |
| Referido | 16.47 | 276.89 | 16.8x |
| Pagado | 47.58 | 276.89 | 5.8x |

El canal pagado tiene el ratio más bajo por un margen amplio — candidato
para revisar eficiencia de campañas antes de aumentar inversión.

**8) Tasa de fraude mensual** (`exports/08g_tasa_fraude_mensual.csv`): entre
0.5% y 2.35% de las transacciones, sin tendencia clara de aumento dentro de
la ventana de 6 meses.

## Resultado del test A/B

Fuente: `athena/05_ab_test_analysis.sql` (tasas de conversión) +
`scripts/ab_test_significance.py` (z-test de proporciones, ya que Athena SQL
no tiene funciones estadísticas nativas para calcular significancia).

`exports/05_ab_test_conversion_por_variante.csv`:

| Variante | Usuarios | Conversiones | Tasa de conversión |
|---|---:|---:|---:|
| Control | 2,500 | 188 | 7.52% |
| Test | 2,500 | 276 | 11.04% |

`exports/05b_ab_test_diferencia_tasas_control_vs_test.csv`: diferencia
absoluta de +0.0352 (3.52 p.p.).

`exports/05c_ab_test_significancia_estadistica.csv` (z-test de proporciones
de dos muestras independientes):

- **z-score**: 4.29
- **p-value**: 1.79e-05
- **Significativo al 95% de confianza**: **Sí**
- **Interpretación**: la variante `test` convierte 46.8% más (relativo) que
  `control`, y la diferencia es estadísticamente muy significativa
  (p muy por debajo de 0.05). Se recomendaría lanzar la variante `test` a
  producción.

## Debugging y decisiones de corrección de datos

Documentado aquí porque son los ajustes que más cambiaron el resultado
final y son los que un revisor técnico (o un entrevistador) más probablemente
preguntaría el "por qué".

### Bug de ventanas solapadas en activación/retención (03_funnel_queries.sql)

**Síntoma**: la primera versión de la query de retención marcaba
`retenido = 1` para prácticamente el 100% de los clientes activados, un
resultado sospechosamente alto.

**Causa raíz**: la condición original de la CTE `retention` era
`pd.purchase_day > a.first_purchase_day` — es decir, "cualquier compra
después de la primera compra". El problema es que la **misma segunda
compra que ya se usó para definir la activación** (dentro de la ventana de
30 días) también cumplía esa condición, así que un cliente se marcaba como
"retenido" usando el mismo evento que ya lo había marcado como "activado".
Esto infla artificialmente la retención porque no mide nada adicional: solo
repite la señal de activación bajo otro nombre.

**Fix**: se cambió la condición a
`date_diff('day', a.first_purchase_day, pd.purchase_day) > 30`, que excluye
explícitamente toda actividad dentro de la ventana de activación y solo
cuenta como retención una compra genuinamente posterior a esos 30 días.
Resultado antes/después:

| Versión | % retención sobre activados |
|---|---:|
| Con bug (ventanas solapadas) | ~100% |
| Corregida | **58.52%** |

### Tablas externas: OpenCSVSerde en vez de `QUOTE CHAR`

Al crear las tablas externas sobre los CSV crudos en S3
(`athena/01_create_external_table_retail.sql`), la sintaxis inicial usaba
`ROW FORMAT DELIMITED ... QUOTE CHAR '"'`. Esa cláusula **no es válida** en
el dialecto Hive/Athena y falla al ejecutar el DDL. La forma correcta de
manejar campos CSV con comillas y escapes (necesario porque
`Description` en Online Retail II trae comas dentro de texto libre) es el
SerDe `org.apache.hadoop.hive.serde2.OpenCSVSerde` con las propiedades de
separador/comilla/escape dentro de `WITH SERDEPROPERTIES (...)`. Efecto
colateral: con este SerDe **todas las columnas se leen como STRING**, por lo
que cualquier columna numérica de las tablas `raw_*` (ej.
`raw_ab_test.converted`, `raw_acquisition_costs.acquisition_cost_pen`)
requiere `CAST` explícito en las queries de análisis — documentado en el
encabezado de cada archivo `.sql` que las usa.

## Decisiones técnicas

- **¿Por qué Athena?** Es el motor de consulta serverless de AWS sobre datos
  en S3 (basado en Trino/Presto). Permite ejercitar SQL analítico sobre
  volúmenes grandes sin levantar infraestructura de base de datos, un patrón
  común para analítica de growth sobre data lakes en S3.
- **¿Por qué CTAS a Parquet particionado (`athena/02_ctas_parquet_partitioned.sql`)
  en vez de consultar el CSV crudo directamente?** Comparación real medida
  en este proyecto sobre la tabla de Online Retail:

  | Formato | Bytes escaneados (query de funnel típica) |
  |---|---:|
  | CSV crudo (`raw_online_retail`) | ~74.56 MB |
  | Parquet particionado por year/month (`online_retail_parquet`) | ~17 KB |

  Esto es una reducción de más del 99% en bytes escaneados para la misma
  consulta. Razones:
  - Parquet es columnar: Athena solo lee las columnas referenciadas en el
    `SELECT`, no la fila completa como en un CSV de texto plano.
  - Compresión columnar (Snappy) reduce el tamaño en disco frente a CSV sin
    comprimir.
  - El particionado por `year`/`month` habilita *partition pruning*: una
    query con filtro por partición ni siquiera abre los archivos de las
    demás particiones.
  - Athena cobra por bytes escaneados (~$5/TB), así que esta reducción se
    traduce directamente en menor costo y menor latencia — una
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

# 5) En la consola de Athena, correr en orden (una sentencia a la vez):
#    athena/01_create_external_table_retail.sql
#    athena/02_ctas_parquet_partitioned.sql
#    athena/03 a athena/08 (queries de análisis)

# 6) Calcular significancia del test A/B
python scripts/ab_test_significance.py --input data/ab_test_data.csv --output exports/05c_ab_test_significancia_estadistica.csv
```

## Dashboard

El análisis completo se visualiza en **Power BI**, conectado a los CSVs
reales de `exports/` (el enfoque simple descrito más abajo).

- **Archivo**: [`dashboard/growth-funnel-dashboard.pbix`](dashboard/growth-funnel-dashboard.pbix)
- **Para abrirlo**: se necesita **Power BI Desktop** (gratuito, solo
  Windows) — [descarga aquí](https://www.microsoft.com/en-us/power-platform/products/power-bi/desktop).

El dashboard tiene 4 páginas:

| Página | Qué muestra |
|---|---|
| **Funnel & Cohortes** | Funnel transaccional de adquisición → activación → retención (Online Retail II) y la matriz de cohortes mensuales, incluyendo la alerta de caída de retención. |
| **Producto & Engagement** | Funnel de activación de producto (signup → ... → first_transaction), tiempos entre etapas, y la serie DAU/MAU con stickiness semanal. |
| **A/B Test** | Tasas de conversión por variante, diferencia absoluta/relativa, y el resultado del z-test de significancia estadística. |
| **Negocio & Riesgo** | Las 8 métricas de negocio: CAC por canal, aprobación de KYC, TPV, ARPU, LTV simplificado, ratio LTV:CAC por canal, y tasa de fraude mensual. |

### Cómo conectar Power BI a los datos

**Opción recomendada (simple, la usada en este proyecto)**: exportar los
resultados de cada query de Athena a CSV (botón "Download results" en la
consola) y cargarlos como archivos en Power BI Desktop. Es el enfoque usado
para generar los CSVs de `exports/` y alimentar
`dashboard/growth-funnel-dashboard.pbix`.

**Opción avanzada (conexión en vivo)**: Power BI puede conectarse
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

- Ningún dato de este proyecto corresponde a usuarios ni transacciones
  reales de ninguna empresa.
- Online Retail II es un dataset público de investigación (UCI) sin
  información personal identificable más allá de un `CustomerID` numérico
  anonimizado.
- Los eventos de producto, KYC, montos y test A/B son enteramente
  sintéticos, generados con semillas fijas (`seed=42`) para reproducibilidad.
