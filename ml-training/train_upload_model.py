#!/usr/bin/env python3
"""
Entrena un artefacto mínimo de recomendaciones (popularidad por ítem desde DynamoDB)
por tenant y lo sube a S3 como JSON. Variables alineadas con Quarkus:
RECOMMENDATIONS_MODEL_S3_BUCKET + RECOMMENDATIONS_MODEL_S3_KEY_PATTERN (placeholder {tenantId}).

Los tenants se obtienen de la tabla PostgreSQL `restaurants` (mismo `id` que en Dynamo `TENANT#...`),
salvo que se defina `TENANT_IDS` para forzar una lista fija.

Credenciales: `DB_USER`/`DB_PASS` o, en AWS, `DB_SECRET_ARN` (JSON de Secrets Manager con `username` y
`password`, formato típico de RDS; opcionalmente `host`, `port`, `dbname` si no defines `DB_URL`).
"""
from __future__ import annotations

import json
import os
import sys
import datetime
import urllib.parse
from collections import defaultdict
from typing import Any

import boto3
import psycopg2
from botocore.exceptions import ClientError

dynamodb = boto3.client("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
s3 = boto3.client("s3", region_name=os.environ.get("AWS_REGION", "us-east-1"))

EVENTS_TABLE = os.environ.get("EVENTS_TABLE", "menudigital-events")
# Deben coincidir con el KeySchema de la tabla (en el repo Quarkus: PK + SK).
PK_ATTR = os.environ.get("DYNAMODB_PK_ATTR", "PK")
SK_ATTR = os.environ.get("DYNAMODB_SK_ATTR", "SK")

DEFAULT_KEY_PATTERN = "recommendations/{tenantId}/model.json"


def _load_db_secret() -> dict[str, Any] | None:
    """Secreto JSON de AWS (mismo formato que usa Quarkus). None si no hay DB_SECRET_ARN."""
    arn = (os.environ.get("DB_SECRET_ARN") or "").strip()
    if not arn:
        return None
    sm = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
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
    """DB_URL + DB_USER/DB_PASS, o DB_SECRET_ARN (y opcionalmente host en el secreto si falta DB_URL)."""
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
    """Override con TENANT_IDS; si no, todos los `restaurants.id` en PostgreSQL."""
    raw = os.environ.get("TENANT_IDS", "").strip()
    if raw:
        return [t.strip() for t in raw.split(",") if t.strip()]
    return fetch_tenant_ids_from_postgres()


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


def build_artifact_for_tenant(tenant_id: str, date_str: str) -> dict[str, Any]:
    counts = query_item_views_for_day(tenant_id, date_str)
    return {
        "artifact_version": 3,
        "trained_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source_day": date_str,
        "tenant_id": tenant_id,
        "item_popularity": counts,
    }


def main() -> int:
    bucket = (os.environ.get("RECOMMENDATIONS_MODEL_S3_BUCKET") or "").strip()
    pattern = (os.environ.get("RECOMMENDATIONS_MODEL_S3_KEY_PATTERN") or "").strip() or DEFAULT_KEY_PATTERN
    if not bucket:
        print(
            "ERROR: Define RECOMMENDATIONS_MODEL_S3_BUCKET",
            file=sys.stderr,
        )
        return 1
    if "{tenantId}" not in pattern:
        print(
            "ERROR: RECOMMENDATIONS_MODEL_S3_KEY_PATTERN debe contener el literal {tenantId} "
            f"(ej. {DEFAULT_KEY_PATTERN})",
            file=sys.stderr,
        )
        return 1

    try:
        tenant_ids = get_all_tenants()
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    if not tenant_ids:
        print(
            "ERROR: No hay filas en la tabla restaurants (o TENANT_IDS está vacío).",
            file=sys.stderr,
        )
        return 1

    yesterday = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
    date_str = yesterday.strftime("%Y-%m-%d")

    uploaded = 0
    for tenant_id in tenant_ids:
        artifact = build_artifact_for_tenant(tenant_id, date_str)
        key = pattern.replace("{tenantId}", tenant_id)
        body = json.dumps(artifact, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=body,
            ContentType="application/json",
        )
        n_items = len(artifact["item_popularity"])
        print(f"OK: s3://{bucket}/{key} ({len(body)} bytes, {n_items} ítems con vistas)")
        uploaded += 1

    print(f"Hecho: {uploaded} modelo(s), día fuente={date_str}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
