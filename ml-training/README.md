# Entrenamiento del modelo de recomendaciones

Hay **tres formas** de ejecutar el mismo pipeline (popularidad `ITEM_VIEW` por tenant → JSON en S3):

1. **CLI** `train_upload_model.py` (local o EC2 con cron).
2. **CLI solo encolado**: `TRAINING_USE_SQS_FANOUT=1` + `TRAINING_JOB_QUEUE_URL` (útil para pruebas con la misma cola que en AWS).
3. **AWS Lambda (fan-out)**: orquestador lista tenants y envía **SQS**; **workers** procesan un mensaje = un tenant (infra en Terraform, `enable_recommendations_fanout`).

El backend Quarkus lee los JSON desde S3 (`RecommendationModelLoader` + `RecommendMenuItemsUseCase`).

## Código compartido

- `**recommendations_etl.py`**: PostgreSQL, DynamoDB, S3, encolado SQS.
- `**orchestrator_lambda.handler**`: tenants → mensajes en cola.
- `**worker_lambda.handler**`: mensaje → agregación + `PutObject`.

## Requisitos (CLI)

- Python 3.10+
- Credenciales AWS con `dynamodb:Query` y `s3:PutObject` en el bucket de modelos.
- Acceso a PostgreSQL (`restaurants`) salvo `TENANT_IDS`.

## Variables de entorno (CLI y Lambdas)


| Variable                                | Descripción                                                               |
| --------------------------------------- | ------------------------------------------------------------------------- |
| `AWS_REGION`                            | Región (ej. `us-east-1`)                                                  |
| `EVENTS_TABLE`                          | Tabla de eventos (ej. `menudigital-events`)                               |
| `RECOMMENDATIONS_MODEL_S3_BUCKET`       | Bucket de modelos                                                         |
| `RECOMMENDATIONS_MODEL_S3_KEY_PATTERN`  | Patrón con `{tenantId}` (default `recommendations/{tenantId}/model.json`) |
| `DB_URL`, `DB_USER`, `DB_PASS`          | Conexión PostgreSQL (o `DB_SECRET_ARN`, ver guía despliegue)              |
| `DB_SECRET_ARN`                         | Secreto tipo RDS (opcional)                                               |
| `TENANT_IDS`                            | Lista fija de UUIDs; si existe, no se consulta PostgreSQL                 |
| `TRAINING_JOB_QUEUE_URL`                | URL de la cola SQS (solo fan-out)                                         |
| `TRAINING_USE_SQS_FANOUT`               | `1` / `true`: el CLI solo encola, no sube a S3                            |
| `DYNAMODB_PK_ATTR` / `DYNAMODB_SK_ATTR` | Opcional (default `PK` / `SK`)                                            |


## Uso CLI (procesamiento local completo)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export AWS_REGION=us-east-1
export EVENTS_TABLE=menudigital-events
export DB_URL=jdbc:postgresql://localhost:5432/menudigital
export DB_USER=menudigital
export DB_PASS=menudigital
export RECOMMENDATIONS_MODEL_S3_BUCKET=menudigital-models-ACCOUNT
python3 train_upload_model.py
```

## Fan-out solo encolado (CLI + misma cola que Lambda)

```bash
export TRAINING_USE_SQS_FANOUT=1
export TRAINING_JOB_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/123456789012/cola
python3 train_upload_model.py
```

## Lambda + SQS (Terraform)

1. Construir artefactos (Linux x86_64; en macOS/ARM usar contenedor):

```bash
# En Linux (o CI x86_64)
bash ml-training/scripts/build_lambda_dists.sh

# Ejemplo en macOS con Docker
docker run --rm -v "$(pwd)/ml-training:/opt/ml" -w /opt/ml \
  public.ecr.aws/sam/build-python3.12 bash scripts/build_lambda_dists.sh
```

1. En `infrastructure/terraform/terraform.tfvars`:

```hcl
enable_recommendations_fanout = true
# Opcional:
# recommendations_fanout_schedule_expression = "cron(15 4 * * ? *)"
# recommendations_fanout_worker_reserved_concurrency = 10
```

1. `terraform apply` (tras `terraform init`).

La **Lambda orquestadora** va en VPC (subredes backend + NAT) para RDS y Secrets Manager; la **worker** no usa VPC (DynamoDB/S3 vía endpoints de gateway en la VPC de la cuenta o API regional).

Mensaje SQS (JSON): `{"tenant_id":"<uuid>","source_day":"YYYY-MM-DD"}`. **ReportBatchItemFailures** reintenta solo mensajes fallidos.

##  Cron (EC2, modo CLI clásico)

```cron
15 4 * * * cd /opt/menudigital/ml-training && . .venv/bin/activate && ... python3 train_upload_model.py >> /var/log/menudigital-model.log 2>&1
```

Tras actualizar JSON en S3, la API puede cachear por tenant hasta reinicio (ver guía backend).

## Formato del JSON (`item_popularity`)

```json
{
  "artifact_version": 3,
  "trained_at": "2026-05-15T04:15:00+00:00",
  "source_day": "2026-05-14",
  "tenant_id": "<uuid>",
  "item_popularity": { "<item-uuid>": 12 }
}
```

## Notas

- IAM de la API: `s3:GetObject` sobre el prefijo de modelos.
- Cola estándar SQS + DLQ con reintentos; ajustar `visibility_timeout` en Terraform si los workers tardan más.

