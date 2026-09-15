# Datos

- `online_retail_ii_clean.csv` **no está versionado** (pesa ~78MB). Para
  regenerarlo: descargar `online_retail_II.xlsx` desde
  [UCI - Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii)
  y correr `python ../scripts/clean_online_retail.py --input online_retail_II.xlsx --output online_retail_ii_clean.csv`.
- `product_events.csv`, `acquisition_costs.csv`, `ab_test_data.csv` son
  sintéticos y sí están versionados (son pequeños y reproducibles con
  `seed=42`, ver README principal del proyecto).
