"""
Genera los CSV de exports/ replicando en pandas la lógica de las queries de
Athena (athena/03 a athena/08), para poder ver resultados y alimentar
Power BI sin necesidad de tener ya desplegado un bucket S3 + Athena.

En un flujo real de producción, estos exports se generarían corriendo las
queries de athena/*.sql directamente en Athena (vía consola, boto3, o el
conector ODBC de Power BI) y descargando el resultado. Este script es un
atajo reproducible para desarrollo local y para que el portafolio tenga
salidas de ejemplo versionadas.

Uso:
    python generate_exports_local.py
"""

import pandas as pd
import numpy as np

DATA_DIR = "../data"
EXPORTS_DIR = "../exports"


def load_data():
    retail = pd.read_csv(f"{DATA_DIR}/online_retail_ii_clean.csv", parse_dates=["InvoiceDate"])
    events = pd.read_csv(f"{DATA_DIR}/product_events.csv", parse_dates=["event_timestamp"])
    costs = pd.read_csv(f"{DATA_DIR}/acquisition_costs.csv")
    return retail, events, costs


def transactional_funnel(retail: pd.DataFrame) -> pd.DataFrame:
    purchase_days = (
        retail.assign(purchase_day=retail["InvoiceDate"].dt.floor("D"))
        [["CustomerID", "purchase_day"]]
        .drop_duplicates()
    )
    first_purchase = purchase_days.groupby("CustomerID")["purchase_day"].min().rename("first_purchase_day")
    merged = purchase_days.merge(first_purchase, on="CustomerID")

    activated_customers = set()
    for cust_id, g in merged.groupby("CustomerID"):
        days = sorted(g["purchase_day"].unique())
        first_day = days[0]
        if len(days) > 1 and (days[1] - first_day).days <= 30:
            activated_customers.add(cust_id)

    retained_customers = set()
    for cust_id in activated_customers:
        first_day = first_purchase[cust_id]
        window_end = first_day + pd.DateOffset(months=3)
        cust_days = merged[merged["CustomerID"] == cust_id]["purchase_day"]
        if ((cust_days > first_day) & (cust_days <= window_end)).any():
            retained_customers.add(cust_id)

    acquired = merged["CustomerID"].nunique()
    activated = len(activated_customers)
    retained = len(retained_customers)

    return pd.DataFrame([{
        "clientes_adquiridos": acquired,
        "clientes_activados": activated,
        "clientes_retenidos": retained,
        "pct_activacion": round(100 * activated / acquired, 2),
        "pct_retencion_sobre_activados": round(100 * retained / activated, 2) if activated else 0,
    }])


def cohort_matrix(retail: pd.DataFrame) -> pd.DataFrame:
    df = retail.copy()
    df["activity_month"] = df["InvoiceDate"].dt.to_period("M")
    first_purchase_month = df.groupby("CustomerID")["activity_month"].min().rename("cohort_month")
    df = df.merge(first_purchase_month, on="CustomerID")
    df["month_number"] = (df["activity_month"] - df["cohort_month"]).apply(lambda x: x.n)

    cohort_size = df.groupby("cohort_month")["CustomerID"].nunique().rename("cohort_customers")
    cohort_counts = df.groupby(["cohort_month", "month_number"])["CustomerID"].nunique().rename("active_customers")

    result = cohort_counts.reset_index().merge(cohort_size.reset_index(), on="cohort_month")
    result["pct_retained"] = round(100 * result["active_customers"] / result["cohort_customers"], 2)
    result["cohort_month"] = result["cohort_month"].astype(str)
    return result.sort_values(["cohort_month", "month_number"])


def product_funnel(events: pd.DataFrame) -> pd.DataFrame:
    steps = ["signup", "login", "view_service", "start_application", "complete_kyc"]
    counts = []
    for step in steps:
        n = events[events["event_name"] == step]["user_id"].nunique()
        counts.append((step, n))

    n_kyc_approved = events[(events["event_name"] == "complete_kyc") & (events["kyc_result"] == "kyc_approved")]["user_id"].nunique()
    counts.append(("kyc_approved", n_kyc_approved))

    n_first_txn = events[events["event_name"] == "first_transaction"]["user_id"].nunique()
    counts.append(("first_transaction", n_first_txn))

    df = pd.DataFrame(counts, columns=["event_name", "usuarios_unicos"])
    df["pct_sobre_signup"] = round(100 * df["usuarios_unicos"] / df["usuarios_unicos"].iloc[0], 2)
    df["pct_conversion_paso_anterior"] = round(100 * df["usuarios_unicos"] / df["usuarios_unicos"].shift(1), 2)
    return df


def dau_mau(events: pd.DataFrame) -> pd.DataFrame:
    df = events.copy()
    df["activity_day"] = df["event_timestamp"].dt.floor("D")
    dau = df.groupby("activity_day")["user_id"].nunique().rename("dau")

    all_days = pd.date_range(df["activity_day"].min(), df["activity_day"].max(), freq="D")
    mau_values = {}
    for day in all_days:
        window = df[(df["event_timestamp"] > day - pd.Timedelta(days=30)) & (df["event_timestamp"] <= day)]
        mau_values[day] = window["user_id"].nunique()
    mau = pd.Series(mau_values, name="mau")

    combined = pd.concat([dau, mau], axis=1).fillna(0)
    combined["dau"] = combined["dau"].fillna(0)
    combined["stickiness_pct"] = round(100 * combined["dau"] / combined["mau"].replace(0, np.nan), 2)
    combined["activity_week"] = combined.index.to_period("W").astype(str)

    weekly = combined.groupby("activity_week").agg(
        dau_promedio_semana=("dau", "mean"),
        mau_promedio_semana=("mau", "mean"),
        stickiness_pct_promedio=("stickiness_pct", "mean"),
    ).round(2).reset_index()
    return weekly


def business_metrics(events: pd.DataFrame, costs: pd.DataFrame) -> dict:
    txns = events[events["event_name"].isin(["first_transaction", "repeat_transaction"])].copy()
    txns["month"] = txns["event_timestamp"].dt.to_period("M").astype(str)

    # 1. CAC por canal y mes
    signups = events[events["event_name"] == "signup"].copy()
    signups["month"] = signups["event_timestamp"].dt.to_period("M").astype(str)
    new_users = signups.groupby(["channel", "month"])["user_id"].nunique().rename("nuevos_usuarios").reset_index()
    cac = new_users.merge(costs, on=["channel", "month"])
    cac["cac_pen"] = round(cac["acquisition_cost_pen"] / cac["nuevos_usuarios"], 2)

    # 2. KYC aprobación/rechazo por canal
    kyc = events[events["event_name"] == "complete_kyc"].copy()
    kyc_summary = kyc.groupby("channel")["kyc_result"].value_counts().unstack(fill_value=0)
    kyc_summary["total_kyc"] = kyc_summary.sum(axis=1)
    kyc_summary["pct_aprobacion"] = round(100 * kyc_summary.get("kyc_approved", 0) / kyc_summary["total_kyc"], 2)
    kyc_summary["pct_rechazo"] = round(100 * kyc_summary.get("kyc_rejected", 0) / kyc_summary["total_kyc"], 2)
    kyc_summary = kyc_summary.reset_index()

    # 3-4. TPV mensual y ticket promedio
    monthly = txns.groupby("month").agg(
        tpv_pen=("amount", "sum"),
        n_transacciones=("amount", "count"),
        ticket_promedio_pen=("amount", "mean"),
    ).round(2).reset_index()

    # 5. ARPU mensual
    active_users_month = txns.groupby("month")["user_id"].nunique().rename("usuarios_activos")
    monthly = monthly.merge(active_users_month, on="month")
    monthly["arpu_pen"] = round(monthly["tpv_pen"] / monthly["usuarios_activos"], 2)

    # 6. LTV simplificado
    arpu_promedio = monthly["arpu_pen"].mean()
    retencion_meses = txns.groupby("user_id")["month"].nunique().mean()
    ltv_simplificado = round(arpu_promedio * retencion_meses, 2)

    # 7. LTV:CAC por canal
    cac_por_canal = cac.groupby("channel").apply(
        lambda g: g["acquisition_cost_pen"].sum() / g["nuevos_usuarios"].sum()
    ).rename("cac_promedio_pen").reset_index()
    cac_por_canal["ltv_simplificado_pen"] = ltv_simplificado
    cac_por_canal["ratio_ltv_cac"] = round(cac_por_canal["ltv_simplificado_pen"] / cac_por_canal["cac_promedio_pen"], 2)

    # 8. Tasa de fraude mensual
    fraud_monthly = txns.groupby("month").agg(
        total_transacciones=("is_fraud", "count"),
        transacciones_fraude=("is_fraud", "sum"),
    ).reset_index()
    fraud_monthly["tasa_fraude_pct"] = round(100 * fraud_monthly["transacciones_fraude"] / fraud_monthly["total_transacciones"], 3)

    return {
        "cac_por_canal_mes": cac,
        "kyc_aprobacion_rechazo": kyc_summary,
        "tpv_arpu_mensual": monthly,
        "ltv_cac_por_canal": cac_por_canal,
        "tasa_fraude_mensual": fraud_monthly,
    }


def main():
    retail, events, costs = load_data()

    print("Calculando funnel transaccional...")
    transactional_funnel(retail).to_csv(f"{EXPORTS_DIR}/funnel_transaccional.csv", index=False)

    print("Calculando matriz de cohortes...")
    cohort_matrix(retail).to_csv(f"{EXPORTS_DIR}/cohort_retention_matrix.csv", index=False)

    print("Calculando funnel de producto...")
    product_funnel(events).to_csv(f"{EXPORTS_DIR}/product_funnel.csv", index=False)

    print("Calculando DAU/MAU...")
    dau_mau(events).to_csv(f"{EXPORTS_DIR}/dau_mau_weekly.csv", index=False)

    print("Calculando métricas de negocio...")
    metrics = business_metrics(events, costs)
    for name, df in metrics.items():
        df.to_csv(f"{EXPORTS_DIR}/{name}.csv", index=False)

    print("Exports generados en", EXPORTS_DIR)


if __name__ == "__main__":
    main()
