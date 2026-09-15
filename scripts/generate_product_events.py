"""
Genera datos SINTÉTICOS que simulan el uso de una app de medios de pago /
inclusión financiera (tipo fintech peruana). No son datos reales de ningún
usuario ni empresa: se generan para poder demostrar analítica de producto
(funnel, DAU/MAU, KYC, fraude) que Online Retail II no puede proveer, ya que
es un dataset de e-commerce sin eventos de producto ni KYC.

Genera dos archivos:
  - data/product_events.csv      (eventos de usuario, embudo de activación)
  - data/acquisition_costs.csv   (costo de adquisición por canal y mes)

Uso:
    python generate_product_events.py --n-users 3000 --seed 42 \
        --output-events ../data/product_events.csv \
        --output-costs ../data/acquisition_costs.csv
"""

import argparse
import random
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

CHANNELS = ["organico", "pagado", "referido"]
CHANNEL_WEIGHTS = [0.50, 0.35, 0.15]

EVENT_SEQUENCE = [
    "signup",
    "login",
    "view_service",
    "start_application",
    "complete_kyc",
    "first_transaction",
]


def business_day_weight(dt: datetime) -> float:
    """Más actividad en días laborales (lun-vie) que en fin de semana."""
    return 1.0 if dt.weekday() < 5 else 0.45


def random_timestamp_in_window(start: datetime, end: datetime, rng: random.Random) -> datetime:
    """Elige un timestamp dentro de [start, end], con más peso en días laborales."""
    span_days = max((end - start).days, 1)
    for _ in range(20):
        candidate = start + timedelta(
            days=rng.uniform(0, span_days),
            hours=rng.uniform(0, 24),
        )
        if rng.random() < business_day_weight(candidate):
            return candidate
    return candidate


def gen_amount(rng: np.random.Generator) -> float:
    """Monto de transacción en soles (PEN), distribución realista sesgada a montos bajos."""
    amount = rng.lognormal(mean=3.6, sigma=0.7)
    return round(float(np.clip(amount, 5, 3000)), 2)


def generate_events(n_users: int, seed: int, window_start: datetime, window_end: datetime):
    rng_py = random.Random(seed)
    rng_np = np.random.default_rng(seed)

    rows = []
    user_channels = {}

    for user_idx in range(1, n_users + 1):
        user_id = f"U{user_idx:06d}"
        channel = rng_py.choices(CHANNELS, weights=CHANNEL_WEIGHTS, k=1)[0]
        user_channels[user_id] = channel

        signup_ts = random_timestamp_in_window(window_start, window_end - timedelta(days=90), rng_py)
        rows.append((user_id, channel, "signup", signup_ts, None, None))

        last_ts = signup_ts

        # login (95%)
        if rng_py.random() >= 0.95:
            continue
        last_ts = last_ts + timedelta(hours=rng_py.uniform(0.1, 48))
        rows.append((user_id, channel, "login", last_ts, None, None))

        # view_service (75% de los que hicieron login)
        if rng_py.random() >= 0.75:
            continue
        last_ts = last_ts + timedelta(hours=rng_py.uniform(0.05, 24))
        rows.append((user_id, channel, "view_service", last_ts, None, None))

        # start_application (40% de los que vieron el servicio)
        if rng_py.random() >= 0.40:
            continue
        last_ts = last_ts + timedelta(hours=rng_py.uniform(0.1, 72))
        rows.append((user_id, channel, "start_application", last_ts, None, None))

        # complete_kyc: siempre se completa el intento, pero con resultado aprobado/rechazado
        last_ts = last_ts + timedelta(hours=rng_py.uniform(0.5, 96))
        kyc_result = "kyc_approved" if rng_py.random() < 0.85 else "kyc_rejected"
        rows.append((user_id, channel, "complete_kyc", last_ts, None, kyc_result))

        if kyc_result != "kyc_approved":
            continue

        # first_transaction (85% de los KYC aprobados) = activación
        if rng_py.random() >= 0.85:
            continue
        last_ts = last_ts + timedelta(hours=rng_py.uniform(0.1, 48))
        amount = gen_amount(rng_np)
        is_fraud = rng_py.random() < 0.015
        rows.append((user_id, channel, "first_transaction", last_ts, amount, "fraud" if is_fraud else "legit"))

        # repeat_transaction: fracción de activados repite en las siguientes 8-12 semanas
        if rng_py.random() < 0.65:
            n_repeats = rng_py.randint(1, 15)
            cursor = last_ts
            for _ in range(n_repeats):
                gap_days = rng_py.uniform(1, 10)
                cursor = cursor + timedelta(days=gap_days)
                if cursor > window_end:
                    break
                if (cursor - last_ts).days > 12 * 7:
                    break
                repeat_amount = gen_amount(rng_np)
                repeat_fraud = rng_py.random() < 0.015
                rows.append((
                    user_id, channel, "repeat_transaction", cursor,
                    repeat_amount, "fraud" if repeat_fraud else "legit",
                ))

    df = pd.DataFrame(rows, columns=["user_id", "channel", "event_name", "event_timestamp", "amount", "result"])

    # is_fraud explícito para transacciones (NULL para eventos no transaccionales)
    is_transaction = df["event_name"].isin(["first_transaction", "repeat_transaction"])
    df["is_fraud"] = np.where(is_transaction, df["result"] == "fraud", np.nan)
    df["is_fraud"] = df["is_fraud"].astype("boolean")
    df.loc[~is_transaction, "is_fraud"] = pd.NA

    # kyc_result solo aplica a complete_kyc
    df["kyc_result"] = df["result"].where(df["event_name"] == "complete_kyc")

    df = df.drop(columns=["result"])
    df = df.sort_values(["user_id", "event_timestamp"]).reset_index(drop=True)
    return df


def generate_acquisition_costs(user_channels_df: pd.DataFrame, window_start: datetime, window_end: datetime, seed: int) -> pd.DataFrame:
    """Costo total invertido por canal y mes (inventado pero razonable, para CAC)."""
    rng = np.random.default_rng(seed + 1)

    signup_month = user_channels_df.copy()
    signup_month["month"] = signup_month["signup_ts"].dt.to_period("M").astype(str)
    new_users_by_channel_month = (
        signup_month.groupby(["channel", "month"])["user_id"].nunique().reset_index(name="new_users")
    )

    base_cost_per_user = {"pagado": 45.0, "referido": 15.0, "organico": 3.0}

    rows = []
    for _, r in new_users_by_channel_month.iterrows():
        channel = r["channel"]
        base = base_cost_per_user[channel]
        noise = rng.uniform(0.85, 1.25)
        total_cost = round(r["new_users"] * base * noise, 2)
        rows.append((channel, r["month"], total_cost))

    return pd.DataFrame(rows, columns=["channel", "month", "acquisition_cost_pen"])


def main():
    parser = argparse.ArgumentParser(description="Genera eventos sintéticos de producto fintech")
    parser.add_argument("--n-users", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output-events", default="../data/product_events.csv")
    parser.add_argument("--output-costs", default="../data/acquisition_costs.csv")
    args = parser.parse_args()

    window_end = datetime(2024, 6, 30)
    window_start = window_end - timedelta(days=180)  # 6 meses

    print(f"Generando eventos de producto para {args.n_users} usuarios (seed={args.seed})...")
    df = generate_events(args.n_users, args.seed, window_start, window_end)
    df.to_csv(args.output_events, index=False)
    print(f"Guardado: {args.output_events} ({len(df)} eventos)")

    signup_ts_by_user = (
        df[df["event_name"] == "signup"][["user_id", "channel", "event_timestamp"]]
        .rename(columns={"event_timestamp": "signup_ts"})
    )
    costs_df = generate_acquisition_costs(signup_ts_by_user, window_start, window_end, args.seed)
    costs_df.to_csv(args.output_costs, index=False)
    print(f"Guardado: {args.output_costs} ({len(costs_df)} filas)")

    print("\nResumen de embudo (usuarios únicos por evento):")
    for ev in EVENT_SEQUENCE:
        print(f"  {ev}: {df[df['event_name'] == ev]['user_id'].nunique()}")
    print(f"  repeat_transaction (usuarios con >=1 repetición): "
          f"{df[df['event_name'] == 'repeat_transaction']['user_id'].nunique()}")


if __name__ == "__main__":
    main()
