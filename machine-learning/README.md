# Entrenamiento del modelo de recomendaciones (batch en EC2)

El script **`train_upload_model.py`** lee eventos `ITEM_VIEW` en DynamoDB (`menuqr-events`), construye un artefacto mínimo (popularidad por ítem, joblib) y lo sube a S3. El backend Quarkus puede cargarlo al arranque vía `RECOMMENDATIONS_MODEL_S3_*` (`RecommendationModelLoader`).

## Requisitos

- Python 3.10+
- Credenciales AWS con `dynamodb:Query` sobre la tabla de eventos (e índices si aplica) y **`s3:PutObject`** en el bucket de modelos (ver [aws-deploy-guide.md](../infrastructure/aws-deploy-guide.md) §8.2).

## Variables de entorno

| Variable | Descripción |
|----------|-------------|
| `AWS_REGION` | Región (ej. `us-east-1`) |
| `EVENTS_TABLE` | Tabla de eventos (ej. `menuqr-events`) |
| `RECOMMENDATIONS_MODEL_S3_BUCKET` | Bucket de modelos |
| `RECOMMENDATIONS_MODEL_S3_KEY` | Clave del objeto (ej. `recommendations/v1/model.joblib`) |
| `TENANT_IDS` | Opcional: lista separada por comas; si falta, usa un tenant de demo |
| `DYNAMODB_PK_ATTR` / `DYNAMODB_SK_ATTR` | Opcional: nombres de la clave HASH y RANGE en la tabla (por defecto `PK` y `SK`) |

## Uso local o en EC2

Desde el directorio `machine-learning` del repo:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export AWS_REGION=us-east-1
export EVENTS_TABLE=menuqr-events
export RECOMMENDATIONS_MODEL_S3_BUCKET=menuqr-models-ACCOUNT
export RECOMMENDATIONS_MODEL_S3_KEY=recommendations/v1/model.joblib
python3 train_upload_model.py
```

**Cron** (las instancias API recargan el objeto **solo al reiniciar** el contenedor/JVM hoy):

```cron
15 4 * * * cd /opt/menuqr/MenuQR/machine-learning && . .venv/bin/activate && AWS_REGION=us-east-1 EVENTS_TABLE=menuqr-events RECOMMENDATIONS_MODEL_S3_BUCKET=... RECOMMENDATIONS_MODEL_S3_KEY=... python3 train_upload_model.py >> /var/log/menuqr-model.log 2>&1
```

Guía paso a paso (SSH, dependencias, prueba, cron diario): [GUIA-EC2-CRON.md](./GUIA-EC2-CRON.md).

## Notas

- El formato del artefacto es joblib (dict versionado); está pensado para poder sustituir por ONNX u otro formato más adelante.
- La inferencia en Quarkus puede seguir siendo mock hasta cablear el consumo del artefacto cargado.
