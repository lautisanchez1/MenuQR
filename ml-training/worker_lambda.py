"""Lambda: un mensaje SQS = un tenant; agrega DynamoDB y sube MREC + joblib a S3."""
from __future__ import annotations

import json
from typing import Any

import recommendations_etl as etl


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    failures: list[dict[str, str]] = []
    for record in event.get("Records", []):
        mid = record.get("messageId", "")
        try:
            body = json.loads(record.get("body", "{}"))
            tenant_id = body.get("tenant_id")
            if not tenant_id or not str(tenant_id).strip():
                raise ValueError("Mensaje sin tenant_id")
            source_day = body.get("source_day") or etl.default_source_day_utc()
            source_day = str(source_day).strip()
            uri_bin, uri_jl, nbytes, nitems = etl.upload_artifact_for_tenant(str(tenant_id).strip(), source_day)
            print(f"OK {tenant_id} -> MREC {uri_bin} ({nbytes} B), joblib {uri_jl}, {nitems} ítems")
        except Exception as e:
            print(f"ERROR messageId={mid}: {e}")
            if mid:
                failures.append({"itemIdentifier": mid})
    return {"batchItemFailures": failures}
