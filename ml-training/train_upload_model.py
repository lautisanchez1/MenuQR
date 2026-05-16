#!/usr/bin/env python3
"""
CLI: entrena artefactos de recomendaciones (popularidad por ítem desde DynamoDB) por tenant.

Modo local (por defecto): procesa cada tenant y sube a S3.

Modo fan-out SQS (TRAINING_USE_SQS_FANOUT=1 y TRAINING_JOB_QUEUE_URL): solo encola mensajes;
el procesamiento lo hacen las Lambdas worker (ver infra Terraform + orchestrator_lambda / worker_lambda).
"""
from __future__ import annotations

import os
import sys

import recommendations_etl as etl


def main() -> int:
    bucket = etl.recommendations_bucket()
    pattern = etl.s3_key_pattern()
    if not bucket:
        print("ERROR: Define RECOMMENDATIONS_MODEL_S3_BUCKET", file=sys.stderr)
        return 1
    if "{tenantId}" not in pattern:
        print(
            "ERROR: RECOMMENDATIONS_MODEL_S3_KEY_PATTERN debe contener el literal {tenantId} "
            f"(ej. {etl.DEFAULT_KEY_PATTERN})",
            file=sys.stderr,
        )
        return 1

    try:
        tenant_ids = etl.get_all_tenants()
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    if not tenant_ids:
        print(
            "ERROR: No hay filas en la tabla restaurants (o TENANT_IDS está vacío).",
            file=sys.stderr,
        )
        return 1

    source_day = etl.default_source_day_utc()
    queue_url = (os.environ.get("TRAINING_JOB_QUEUE_URL") or "").strip()
    fanout = os.environ.get("TRAINING_USE_SQS_FANOUT", "").strip().lower() in ("1", "true", "yes")

    if fanout:
        if not queue_url:
            print("ERROR: TRAINING_USE_SQS_FANOUT requiere TRAINING_JOB_QUEUE_URL", file=sys.stderr)
            return 1
        n = etl.enqueue_tenant_jobs(queue_url, tenant_ids, source_day)
        print(f"Encolados {n} trabajo(s) en SQS, día fuente={source_day}")
        return 0

    uploaded = 0
    for tenant_id in tenant_ids:
        uri, nbytes, nitems = etl.upload_artifact_for_tenant(tenant_id, source_day)
        print(f"OK: {uri} ({nbytes} bytes, {nitems} ítems con vistas)")
        uploaded += 1

    print(f"Hecho: {uploaded} modelo(s), día fuente={source_day}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
