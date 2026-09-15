"""
Calcula la significancia estadística del test A/B (z-test de proporciones de
dos muestras independientes), ya que Athena SQL no tiene funciones
estadísticas nativas para esto.

Usa como input el resultado de athena/05_ab_test_analysis.sql (tasas de
conversión por variante) o recalcula directamente desde data/ab_test_data.csv.

Uso:
    python ab_test_significance.py --input ../data/ab_test_data.csv
"""

import argparse
import math

import pandas as pd
from scipy import stats


def two_proportion_z_test(conv_control, n_control, conv_test, n_test):
    p_control = conv_control / n_control
    p_test = conv_test / n_test
    p_pool = (conv_control + conv_test) / (n_control + n_test)

    se = math.sqrt(p_pool * (1 - p_pool) * (1 / n_control + 1 / n_test))
    z = (p_test - p_control) / se
    p_value = 2 * (1 - stats.norm.cdf(abs(z)))

    return {
        "tasa_control": p_control,
        "tasa_test": p_test,
        "diferencia_absoluta": p_test - p_control,
        "diferencia_relativa_pct": 100 * (p_test - p_control) / p_control if p_control > 0 else None,
        "z_score": z,
        "p_value": p_value,
        "significativo_95pct": p_value < 0.05,
    }


def main():
    parser = argparse.ArgumentParser(description="Calcula significancia del test A/B")
    parser.add_argument("--input", default="../data/ab_test_data.csv")
    parser.add_argument("--output", default="../exports/ab_test_result.csv")
    args = parser.parse_args()

    df = pd.read_csv(args.input)

    grouped = df.groupby("variant")["converted"].agg(["sum", "count"])
    conv_control, n_control = grouped.loc["control", "sum"], grouped.loc["control", "count"]
    conv_test, n_test = grouped.loc["test", "sum"], grouped.loc["test", "count"]

    result = two_proportion_z_test(conv_control, n_control, conv_test, n_test)

    print("Resultado del test A/B (z-test de proporciones):")
    for k, v in result.items():
        print(f"  {k}: {v}")

    result_df = pd.DataFrame([result])
    result_df.to_csv(args.output, index=False)
    print(f"\nGuardado: {args.output}")


if __name__ == "__main__":
    main()
