#!/usr/bin/env python3
"""
Entrena un artefacto mínimo de recomendaciones (popularidad por ítem desde DynamoDB)
y lo sube a S3. Mismas variables que el backend Quarkus: RECOMMENDATIONS_MODEL_S3_*.

El backend solo almacena los bytes por ahora (inferencia mock); el formato es joblib
(pickle) con un dict versionado para poder sustituir por ONNX más adelante.
"""
from __future__ import annotations

import io
import os
import sys
import datetime
from collections import defaultdict
from typing import Any

import boto3
from botocore.exceptions import ClientError
import joblib
import numpy as np
from sklearn.dummy import DummyClassifier

dynamodb = boto3.client("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
s3 = boto3.client("s3", region_name=os.environ.get("AWS_REGION", "us-east-1"))

EVENTS_TABLE = os.environ.get("EVENTS_TABLE", "menuqr-events")
# Deben coincidir con el KeySchema de la tabla (en el repo Quarkus: PK + SK).
PK_ATTR = os.environ.get("DYNAMODB_PK_ATTR", "PK")
SK_ATTR = os.environ.get("DYNAMODB_SK_ATTR", "SK")


def get_all_tenants() -> list[str]:
    """Lista de tenants a entrenar; en prod sustituir por consulta a RDS/API."""
    raw = os.environ.get("TENANT_IDS", "")
    if raw.strip():
        return [t.strip() for t in raw.split(",") if t.strip()]
    return ["550e8400-e29b-41d4-a716-446655440000"]


def query_item_views_for_day(tenant_id: str, date_str: str) -> dict[str, int]:
    pk = f"TENANT#{tenant_id}"
    start_sk = f"EVENT#{date_str}T00:00:00.000Z"
    end_sk = f"EVENT#{date_str}T23:59:59.999Z"
    counts: dict[str, int] = defaultdict(int)
    paginator = dynamodb.get_paginator("query")
    try:
        for page in paginator.paginate(
            TableName=EVENTS_TABLE,
            KeyConditionExpression="#p = :pk AND #s BETWEEN :a AND :b",
            ExpressionAttributeNames={"#p": PK_ATTR, "#s": SK_ATTR},
            ExpressionAttributeValues={
                ":pk": {"S": pk},
                ":a": {"S": start_sk},
                ":b": {"S": end_sk},
            },
        ):
            for item in page.get("Items", []):
                if item.get("eventType", {}).get("S") != "ITEM_VIEW":
                    continue
                iid = item.get("itemId", {}).get("S")
                if iid:
                    counts[iid] += 1
    except ClientError as e:
        err = e.response.get("Error", {})
        code = err.get("Code", "")
        msg = err.get("Message", str(e))
        print(
            "ERROR DynamoDB Query. Comprueba región (AWS_REGION), nombre de tabla (EVENTS_TABLE) "
            f"y que la tabla tenga clave HASH+RANGE con atributos '{PK_ATTR}' y '{SK_ATTR}'.\n"
            "  aws dynamodb describe-table --table-name "
            f"{EVENTS_TABLE} --region {os.environ.get('AWS_REGION', 'us-east-1')}\n"
            f"  ({code}: {msg})",
            file=sys.stderr,
        )
        raise
    return dict(counts)


def build_artifact() -> dict[str, Any]:
    yesterday = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
    date_str = yesterday.strftime("%Y-%m-%d")

    by_tenant: dict[str, dict[str, int]] = {}
    global_counts: dict[str, int] = defaultdict(int)

    for tenant_id in get_all_tenants():
        day_counts = query_item_views_for_day(tenant_id, date_str)
        by_tenant[tenant_id] = day_counts
        for iid, c in day_counts.items():
            global_counts[iid] += c

    # Vector trivial para adjuntar un estimador sklearn serializable (placeholder)
    X = np.array([[0.0, float(sum(global_counts.values()) or 0)]])
    y = np.array([0])
    dummy = DummyClassifier(strategy="most_frequent")
    dummy.fit(X, y)

    return {
        "artifact_version": 2,
        "trained_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source_day": date_str,
        "item_popularity_by_tenant": by_tenant,
        "item_popularity_global": dict(global_counts),
        "placeholder_estimator": dummy,
    }


def main() -> int:
    bucket = (os.environ.get("RECOMMENDATIONS_MODEL_S3_BUCKET") or "").strip()
    key = (os.environ.get("RECOMMENDATIONS_MODEL_S3_KEY") or "").strip()
    if not bucket or not key:
        print(
            "ERROR: Define RECOMMENDATIONS_MODEL_S3_BUCKET y RECOMMENDATIONS_MODEL_S3_KEY",
            file=sys.stderr,
        )
        return 1

    artifact = build_artifact()
    buf = io.BytesIO()
    joblib.dump(artifact, buf, compress=3)
    body = buf.getvalue()

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/octet-stream",
    )
    print(
        f"OK: subido s3://{bucket}/{key} ({len(body)} bytes), "
        f"día fuente={artifact['source_day']}, tenants={list(artifact['item_popularity_by_tenant'].keys())}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
