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

    significativo = p_value < 0.05
    interpretacion = (
        f"La variante 'test' convierte {100*p_test:.2f}% vs. {100*p_control:.2f}% de 'control' "
        f"(+{100*(p_test-p_control):.2f} p.p., {100*(p_test-p_control)/p_control:+.1f}% relativo). "
        + (
            f"Con z={z:.2f} y p={p_value:.2e} (< 0.05), la diferencia es estadísticamente "
            "significativa al 95% de confianza: se recomienda lanzar la variante 'test'."
            if significativo else
            f"Con z={z:.2f} y p={p_value:.2e} (>= 0.05), la diferencia NO es estadísticamente "
            "significativa al 95% de confianza."
        )
    )

    return {
        "conversiones_control": conv_control,
        "n_control": n_control,
        "conversiones_test": conv_test,
        "n_test": n_test,
        "tasa_control": p_control,
        "tasa_test": p_test,
        "diferencia_absoluta": p_test - p_control,
        "diferencia_relativa_pct": 100 * (p_test - p_control) / p_control if p_control > 0 else None,
        "z_score": z,
        "p_value": p_value,
        "significativo_95pct": significativo,
        "interpretacion": interpretacion,
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
