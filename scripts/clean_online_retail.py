"""
Limpieza del dataset Online Retail II (UCI Machine Learning Repository).
Fuente: https://archive.ics.uci.edu/dataset/502/online+retail+ii

Este dataset es DATA REAL de transacciones de e-commerce del Reino Unido
(2009-2011, ~1.07M filas). Se usa como proxy del funnel transaccional
(adquisición -> activación -> retención) porque no existe un dataset público
de comportamiento de usuarios de fintech a nivel de usuario.

Uso:
    python clean_online_retail.py --input online_retail_II.xlsx --output ../data/online_retail_ii_clean.csv

Si el archivo de entrada es .xlsx, se leen ambas hojas (Year 2009-2010 y
Year 2010-2011) y se concatenan, tal como se distribuye en UCI.
"""

import argparse
import sys

import pandas as pd


def load_raw(input_path: str) -> pd.DataFrame:
    if input_path.lower().endswith(".xlsx"):
        sheets = pd.read_excel(input_path, sheet_name=None)
        df = pd.concat(sheets.values(), ignore_index=True)
    else:
        df = pd.read_csv(input_path, encoding="ISO-8859-1")
    return df


def clean(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    stats = {"filas_originales": len(df)}

    # Normalizar nombres de columnas esperados del dataset UCI
    df.columns = [c.strip().replace(" ", "") for c in df.columns]
    rename_map = {
        "Invoice": "InvoiceNo",
        "CustomerID": "CustomerID",
        "Customer ID": "CustomerID",
        "Price": "UnitPrice",
    }
    df = df.rename(columns={k: v for k, v in rename_map.items() if k in df.columns})

    required = ["InvoiceNo", "StockCode", "Description", "Quantity",
                "InvoiceDate", "UnitPrice", "CustomerID", "Country"]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"Faltan columnas esperadas en el archivo fuente: {missing}")

    df["InvoiceNo"] = df["InvoiceNo"].astype(str)

    # 1) Descartar filas sin CustomerID
    sin_customer = df["CustomerID"].isna().sum()
    df = df[df["CustomerID"].notna()].copy()
    stats["filas_sin_customer_id_descartadas"] = int(sin_customer)

    # 2) Descartar cancelaciones (InvoiceNo empieza con 'C')
    es_cancelacion = df["InvoiceNo"].str.startswith("C")
    stats["filas_canceladas_descartadas"] = int(es_cancelacion.sum())
    df = df[~es_cancelacion].copy()

    # 3) Descartar cantidades o precios no positivos (ruido residual del dataset)
    ruido = (df["Quantity"] <= 0) | (df["UnitPrice"] <= 0)
    stats["filas_cantidad_o_precio_no_positivo_descartadas"] = int(ruido.sum())
    df = df[~ruido].copy()

    df["CustomerID"] = df["CustomerID"].astype(int)
    df["InvoiceDate"] = pd.to_datetime(df["InvoiceDate"])
    df["TotalPrice"] = df["Quantity"] * df["UnitPrice"]

    stats["filas_finales"] = len(df)
    stats["total_filas_descartadas"] = stats["filas_originales"] - stats["filas_finales"]
    return df, stats


def main():
    parser = argparse.ArgumentParser(description="Limpia el dataset Online Retail II")
    parser.add_argument("--input", required=True, help="Ruta al .xlsx o .csv crudo de UCI")
    parser.add_argument("--output", default="../data/online_retail_ii_clean.csv")
    args = parser.parse_args()

    print(f"Leyendo dataset crudo desde: {args.input}")
    df_raw = load_raw(args.input)

    df_clean, stats = clean(df_raw)

    print("Resumen de limpieza:")
    for k, v in stats.items():
        print(f"  {k}: {v}")

    df_clean.to_csv(args.output, index=False)
    print(f"Dataset limpio guardado en: {args.output} ({len(df_clean)} filas)")


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError as e:
        print(f"Error: no se encontró el archivo de entrada. {e}", file=sys.stderr)
        sys.exit(1)
