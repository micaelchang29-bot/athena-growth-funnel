"""
Genera datos SINTÉTICOS de un test A/B de conversión (por ejemplo, dos
versiones del flujo de onboarding/KYC). No corresponde a ningún experimento
real; sirve para demostrar el pipeline Athena SQL + análisis de significancia.

Uso:
    python generate_ab_test_data.py --n 5000 --seed 42 --output ../data/ab_test_data.csv
"""

import argparse

import numpy as np
import pandas as pd


def generate(n: int, seed: int) -> pd.DataFrame:
    rng = np.random.default_rng(seed)

    n_control = n // 2
    n_test = n - n_control

    control_ids = [f"C{100000 + i}" for i in range(n_control)]
    test_ids = [f"C{100000 + n_control + i}" for i in range(n_test)]

    control_converted = rng.random(n_control) < 0.08
    test_converted = rng.random(n_test) < 0.11

    df_control = pd.DataFrame({
        "customer_id": control_ids,
        "variant": "control",
        "converted": control_converted.astype(int),
    })
    df_test = pd.DataFrame({
        "customer_id": test_ids,
        "variant": "test",
        "converted": test_converted.astype(int),
    })

    df = pd.concat([df_control, df_test], ignore_index=True)
    df = df.sample(frac=1, random_state=seed).reset_index(drop=True)
    return df


def main():
    parser = argparse.ArgumentParser(description="Genera datos sintéticos de test A/B")
    parser.add_argument("--n", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", default="../data/ab_test_data.csv")
    args = parser.parse_args()

    df = generate(args.n, args.seed)
    df.to_csv(args.output, index=False)

    print(f"Guardado: {args.output} ({len(df)} filas)")
    print(df.groupby("variant")["converted"].mean())


if __name__ == "__main__":
    main()
