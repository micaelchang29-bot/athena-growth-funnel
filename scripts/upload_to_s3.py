"""
Sube los 4 datasets CSV a sus prefijos correspondientes en S3, para que
Athena pueda leerlos como tablas externas.

El bucket se parametriza SIEMPRE por variable de entorno (nunca hardcodeado):
    export ATHENA_GROWTH_BUCKET=mi-bucket-de-analitica

Uso:
    python upload_to_s3.py --data-dir ../data
"""

import argparse
import os
import sys
from pathlib import Path

import boto3
from botocore.exceptions import NoCredentialsError, ClientError

PREFIX_MAP = {
    "online_retail_ii_clean.csv": "raw/online_retail/online_retail_ii_clean.csv",
    "product_events.csv": "raw/product_events/product_events.csv",
    "ab_test_data.csv": "raw/ab_test/ab_test_data.csv",
    "acquisition_costs.csv": "raw/acquisition_costs/acquisition_costs.csv",
}


def main():
    parser = argparse.ArgumentParser(description="Sube los CSVs del proyecto a S3")
    parser.add_argument("--data-dir", default="../data")
    args = parser.parse_args()

    bucket = os.environ.get("ATHENA_GROWTH_BUCKET")
    if not bucket:
        print(
            "Error: define la variable de entorno ATHENA_GROWTH_BUCKET con el nombre "
            "de tu bucket S3, por ejemplo:\n"
            "  export ATHENA_GROWTH_BUCKET=mi-bucket-de-analitica  (Linux/Mac)\n"
            "  $env:ATHENA_GROWTH_BUCKET='mi-bucket-de-analitica'  (PowerShell)",
            file=sys.stderr,
        )
        sys.exit(1)

    data_dir = Path(args.data_dir)
    s3 = boto3.client("s3")

    for filename, s3_key in PREFIX_MAP.items():
        local_path = data_dir / filename
        if not local_path.exists():
            print(f"Aviso: no se encontró {local_path}, se omite.")
            continue
        try:
            s3.upload_file(str(local_path), bucket, s3_key)
            print(f"Subido: {local_path} -> s3://{bucket}/{s3_key}")
        except NoCredentialsError:
            print(
                "Error: no se encontraron credenciales de AWS. Configura "
                "`aws configure` o las variables AWS_ACCESS_KEY_ID / "
                "AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN antes de continuar.",
                file=sys.stderr,
            )
            sys.exit(1)
        except ClientError as e:
            print(f"Error subiendo {local_path} a S3: {e}", file=sys.stderr)
            sys.exit(1)

    print("Carga a S3 completada.")


if __name__ == "__main__":
    main()
