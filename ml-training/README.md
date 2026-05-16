# Entrenamiento del modelo de recomendaciones

Hay **tres formas** de ejecutar el pipeline (agregación `ITEM_VIEW` por tenant → S3):

1. **CLI** `train_upload_model.py` (local o EC2 con cron).
2. **CLI solo encolado**: `TRAINING_USE_SQS_FANOUT=1` + `TRAINING_JOB_QUEUE_URL`.
3. **AWS Lambda (fan-out)**: orquestador → **SQS** → workers (Terraform `enable_recommendations_fanout`).

## Artefactos por tenant

| Fichero | Formato | Consumidor |
|---------|---------|------------|
| `…/model.bin` (patrón configurable) | **MREC v4** binario (magic `MREC`, UTF-8, mapa item→conteos) | **API Java** (`RecommendationModelLoader`) |
| mismo prefijo `…/model.joblib` | **joblib** (dict Python: metadatos, `item_popularity`, `placeholder_estimator` sklearn) | Python / notebooks / pipelines ML |

Java **no** lee joblib (pickle); el binario MREC es el contrato estable entre ETL y backend.

## Código

- `recommendations_etl.py` — PostgreSQL, DynamoDB, codificación MREC, `joblib.dump`, SQS.
- `orchestrator_lambda.py` / `worker_lambda.py` — Lambdas.

## CLI rápido (local)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export AWS_REGION=us-east-1
export EVENTS_TABLE=menudigital-events
export DB_URL=jdbc:postgresql://localhost:5432/menudigital
export DB_USER=menudigital
export DB_PASS=menudigital
export RECOMMENDATIONS_MODEL_S3_BUCKET=tu-bucket-ml
python3 train_upload_model.py
```

## Variables de entorno (resumen)

| Variable | Descripción |
|----------|-------------|
| `RECOMMENDATIONS_MODEL_S3_BUCKET` | Bucket (mismo que modelos ML suele bastar) |
| `RECOMMENDATIONS_MODEL_S3_KEY_PATTERN` | Clave del **.bin** con `{tenantId}` (default `recommendations/{tenantId}/model.bin`) |
| `DB_*`, `DB_SECRET_ARN`, `TENANT_IDS`, … | Ver secciones anteriores del repo / guía AWS |

## Build Lambdas

```bash
bash ml-training/scripts/build_lambda_dists.sh
# macOS/ARM: usar imagen public.ecr.aws/sam/build-python3.12 (ver sección anterior en historial / guía Terraform).
```

## Formato MREC v4 (referencia)

Orden **big-endian**:

1. `int32` magic `0x4D524543` (`MREC` como entero)
2. `int32` `artifact_version` (= 4)
3. `int32` len + UTF-8 `trained_at`
4. `int32` len + UTF-8 `source_day`
5. `int32` len + UTF-8 `tenant_id`
6. `int32` `n` entradas
7. `n` veces: `int32` len + UTF-8 `item_id`, `int32` `count`

El decoder Java está en `RecommendationArtifactBinaryCodec`.

## Notas

- Tras cambiar el `.bin` en S3, la API puede tener caché por tenant hasta reinicio.
- El `DummyClassifier` en joblib es un marcador para evolucionar a modelos sklearn reales sin cambiar el nombre del fichero.
