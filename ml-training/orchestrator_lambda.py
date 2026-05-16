"""Lambda: lista tenants (PostgreSQL) y encola un mensaje por tenant en SQS."""
from __future__ import annotations

import os
from typing import Any

import recommendations_etl as etl


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    queue_url = (os.environ.get("TRAINING_JOB_QUEUE_URL") or "").strip()
    if not queue_url:
        raise RuntimeError("TRAINING_JOB_QUEUE_URL no está definido")

    # EventBridge: detail puede traer source_day para reprocesar un día concreto (YYYY-MM-DD)
    source_day = etl.default_source_day_utc()
    if isinstance(event, dict):
        d = event.get("detail") if isinstance(event.get("detail"), dict) else None
        if d and isinstance(d.get("source_day"), str) and d["source_day"].strip():
            source_day = d["source_day"].strip()

    tenant_ids = etl.get_all_tenants()
    if not tenant_ids:
        return {"ok": False, "error": "no_tenants", "enqueued": 0, "source_day": source_day}

    n = etl.enqueue_tenant_jobs(queue_url, tenant_ids, source_day)
    return {"ok": True, "enqueued": n, "source_day": source_day, "tenants": len(tenant_ids)}
