"""
Lógica compartida: tenants (PostgreSQL), agregación DynamoDB, artefacto ML y subida S3.

Por tenant se publican **dos** objetos:
- Fichero binario **MREC** (metadatos + `item_popularity`): lo lee la API Java.
- **joblib** (dict Python con el mismo contenido + `placeholder_estimator` sklearn): pipelines ML / inspección.
"""
from __future__ import annotations

import datetime
import io
import json
import os
import struct
import sys
import urllib.parse
from collections import defaultdict
from typing import Any

import boto3
import joblib
import numpy as np
import psycopg2
from botocore.exceptions import ClientError
from sklearn.dummy import DummyClassifier

# Clave fija; debe coincidir con RecommendationModelLoader (Java) y worker_lambda.py.
MODEL_S3_KEY_PATTERN = "recommendations/{tenantId}/model.bin"

# Magic big-endian int: 'M','R','E','C'
MREC_MAGIC = 0x4D524543
MREC_VERSION = 4


def aws_region() -> str:
    return os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))


def events_table() -> str:
    return os.environ.get("EVENTS_TABLE", "menudigital-events")


def pk_attr() -> str:
    return os.environ.get("DYNAMODB_PK_ATTR", "PK")


def sk_attr() -> str:
    return os.environ.get("DYNAMODB_SK_ATTR", "SK")


def dynamodb_client():
    return boto3.client("dynamodb", region_name=aws_region())


def s3_client():
    return boto3.client("s3", region_name=aws_region())


def sqs_client():
    return boto3.client("sqs", region_name=aws_region())


def _load_db_secret() -> dict[str, Any] | None:
    arn = (os.environ.get("DB_SECRET_ARN") or "").strip()
    if not arn:
        return None
    sm = boto3.client("secretsmanager", region_name=aws_region())
    try:
        resp = sm.get_secret_value(SecretId=arn)
    except ClientError as e:
        raise RuntimeError(f"No se pudo leer DB_SECRET_ARN ({arn}): {e}") from e
    raw = resp.get("SecretString")
    if not raw:
        raise RuntimeError(f"El secreto {arn} no tiene SecretString.")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"DB_SECRET_ARN no contiene JSON válido: {e}") from e
    if not isinstance(data, dict):
        raise RuntimeError("El secreto JSON debe ser un objeto (p. ej. credenciales RDS).")
    return data


def _postgres_connect_kwargs() -> dict[str, Any] | None:
    secret = _load_db_secret()

    db_url = (os.environ.get("DB_URL") or "").strip()
    user = (os.environ.get("DB_USER") or os.environ.get("POSTGRES_USER") or "").strip()
    password = os.environ.get("DB_PASS") or os.environ.get("POSTGRES_PASSWORD") or ""

    if secret:
        su = secret.get("username") or secret.get("user")
        if su is not None and str(su).strip():
            user = str(su).strip()
        if "password" in secret and secret["password"] is not None:
            password = str(secret["password"])

    if db_url.startswith("jdbc:"):
        db_url = db_url[5:]

    host: str | None = None
    port = 5432
    dbname = ""
    sslmode: str | None = None

    if db_url:
        parsed = urllib.parse.urlparse(db_url)
        host = parsed.hostname
        port = parsed.port or 5432
        path = (parsed.path or "").lstrip("/")
        dbname = path.split("?")[0] if path else ""
        q = urllib.parse.parse_qs(parsed.query)
        if "sslmode" in q and q["sslmode"]:
            sslmode = q["sslmode"][0]
    elif secret:
        host = str(secret.get("host") or secret.get("hostname") or "").strip() or None
        pe = secret.get("port")
        if pe is not None:
            try:
                port = int(pe)
            except (TypeError, ValueError):
                port = 5432
        dbname = str(
            secret.get("dbname") or secret.get("database") or secret.get("dbInstanceIdentifier") or "postgres"
        ).strip()
        smode = secret.get("sslmode")
        if isinstance(smode, str) and smode.strip():
            sslmode = smode.strip()
    else:
        host = (os.environ.get("POSTGRES_HOST") or "").strip() or None
        port_s = (os.environ.get("POSTGRES_PORT") or "5432").strip()
        port = int(port_s) if port_s.isdigit() else 5432
        dbname = (os.environ.get("POSTGRES_DB") or "menudigital").strip()

    if not host or not dbname or not user:
        return None

    out: dict[str, Any] = {
        "host": host,
        "port": port,
        "dbname": dbname,
        "user": user,
        "password": password,
        "connect_timeout": 30,
    }
    if sslmode:
        out["sslmode"] = sslmode
    return out


def fetch_tenant_ids_from_postgres() -> list[str]:
    kw = _postgres_connect_kwargs()
    if kw is None:
        raise RuntimeError(
            "Falta configuración PostgreSQL: define DB_URL y credenciales (DB_USER/DB_PASS o DB_SECRET_ARN), "
            "o solo DB_SECRET_ARN si el JSON incluye host/port/dbname (formato RDS), "
            "o POSTGRES_HOST + POSTGRES_DB + usuario/contraseña. Alternativa: TENANT_IDS=uuid1,uuid2."
        )
    try:
        with psycopg2.connect(**kw) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id::text FROM restaurants ORDER BY created_at, id")
                return [row[0] for row in cur.fetchall()]
    except Exception as e:
        raise RuntimeError(
            f"No se pudo conectar a PostgreSQL o leer la tabla restaurants: {e}"
        ) from e


def get_all_tenants() -> list[str]:
    raw = os.environ.get("TENANT_IDS", "").strip()
    if raw:
        return [t.strip() for t in raw.split(",") if t.strip()]
    return fetch_tenant_ids_from_postgres()


def default_source_day_utc() -> str:
    yesterday = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
    return yesterday.strftime("%Y-%m-%d")


def query_item_views_for_day(tenant_id: str, date_str: str) -> dict[str, int]:
    pk = f"TENANT#{tenant_id}"
    start_sk = f"EVENT#{date_str}T00:00:00.000Z"
    end_sk = f"EVENT#{date_str}T23:59:59.999Z"
    counts: dict[str, int] = defaultdict(int)
    dynamodb = dynamodb_client()
    paginator = dynamodb.get_paginator("query")
    try:
        for page in paginator.paginate(
            TableName=events_table(),
            KeyConditionExpression="#p = :pk AND #s BETWEEN :a AND :b",
            ExpressionAttributeNames={"#p": pk_attr(), "#s": sk_attr()},
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
            f"y que la tabla tenga clave HASH+RANGE con atributos '{pk_attr()}' y '{sk_attr()}'.\n"
            "  aws dynamodb describe-table --table-name "
            f"{events_table()} --region {aws_region()}\n"
            f"  ({code}: {msg})",
            file=sys.stderr,
        )
        raise
    return dict(counts)


def _write_utf(buf: bytearray, s: str) -> None:
    b = s.encode("utf-8")
    buf.extend(struct.pack(">I", len(b)))
    buf.extend(b)


def encode_mrec_binary(artifact: dict[str, Any]) -> bytes:
    """Formato MREC v4 (big-endian), alineado con RecommendationArtifactBinaryCodec en Java."""
    buf = bytearray()
    buf.extend(struct.pack(">I", MREC_MAGIC))
    buf.extend(struct.pack(">I", int(artifact.get("artifact_version", MREC_VERSION))))
    _write_utf(buf, str(artifact.get("trained_at", "")))
    _write_utf(buf, str(artifact.get("source_day", "")))
    _write_utf(buf, str(artifact.get("tenant_id", "")))
    pop = artifact.get("item_popularity") or {}
    if not isinstance(pop, dict):
        pop = {}
    buf.extend(struct.pack(">I", len(pop)))
    for item_id, count in sorted(pop.items()):
        _write_utf(buf, str(item_id))
        buf.extend(struct.pack(">i", int(count)))
    return bytes(buf)


def build_artifact_for_tenant(tenant_id: str, date_str: str) -> dict[str, Any]:
    counts = query_item_views_for_day(tenant_id, date_str)
    X = np.array([[0.0, float(sum(counts.values()) or 0)]])
    y = np.array([0])
    dummy = DummyClassifier(strategy="most_frequent")
    dummy.fit(X, y)
    return {
        "artifact_version": MREC_VERSION,
        "trained_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source_day": date_str,
        "tenant_id": tenant_id,
        "item_popularity": counts,
        "placeholder_estimator": dummy,
    }


def joblib_key_for_tenant(tenant_id: str) -> str:
    key_bin = MODEL_S3_KEY_PATTERN.replace("{tenantId}", tenant_id)
    return key_bin[:-4] + ".joblib"


def recommendations_bucket() -> str:
    return (os.environ.get("RECOMMENDATIONS_MODEL_S3_BUCKET") or "").strip()


def upload_artifact_for_tenant(tenant_id: str, source_day: str) -> tuple[str, str, int, int]:
    """
    Sube MREC (.bin) + joblib (.joblib).
    Devuelve (uri_bin, uri_joblib, bytes_bin, num_items_popularity).
    """
    bucket = recommendations_bucket()
    if not bucket:
        raise ValueError("RECOMMENDATIONS_MODEL_S3_BUCKET no está definido")

    artifact = build_artifact_for_tenant(tenant_id, source_day)
    key_bin = MODEL_S3_KEY_PATTERN.replace("{tenantId}", tenant_id)
    key_job = joblib_key_for_tenant(tenant_id)

    mrec_body = encode_mrec_binary(artifact)
    s3_client().put_object(
        Bucket=bucket,
        Key=key_bin,
        Body=mrec_body,
        ContentType="application/octet-stream",
    )

    jl_buf = io.BytesIO()
    joblib.dump(artifact, jl_buf, compress=3)
    jl_bytes = jl_buf.getvalue()
    s3_client().put_object(
        Bucket=bucket,
        Key=key_job,
        Body=jl_bytes,
        ContentType="application/octet-stream",
    )

    n_items = len(artifact["item_popularity"])
    return f"s3://{bucket}/{key_bin}", f"s3://{bucket}/{key_job}", len(mrec_body), n_items


def enqueue_tenant_jobs(
    queue_url: str,
    tenant_ids: list[str],
    source_day: str,
) -> int:
    """Envía un mensaje JSON por tenant a SQS (batches de hasta 10)."""
    sqs = sqs_client()
    for i in range(0, len(tenant_ids), 10):
        chunk = tenant_ids[i : i + 10]
        entries = [
            {
                "Id": str(j),
                "MessageBody": json.dumps({"tenant_id": tid, "source_day": source_day}),
            }
            for j, tid in enumerate(chunk)
        ]
        sqs.send_message_batch(QueueUrl=queue_url, Entries=entries)
    return len(tenant_ids)
