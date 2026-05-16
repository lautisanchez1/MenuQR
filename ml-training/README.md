# Entrenamiento del modelo de recomendaciones (batch en EC2)

El script **`train_upload_model.py`** lee eventos `ITEM_VIEW` en DynamoDB (`menudigital-events`), calcula popularidad por ítem **por tenant** para el día anterior (UTC) y sube **un JSON por tenant** al bucket de modelos S3. El backend Quarkus descarga el JSON del tenant correspondiente al menú (`RecommendationModelLoader` + `RecommendMenuItemsUseCase`).

Por defecto los **tenant = `restaurants.id`** se listan desde la **base PostgreSQL principal** (mismas credenciales que Quarkus: `DB_URL`, `DB_USER`, `DB_PASS`). Opcionalmente `TENANT_IDS` fuerza una lista fija sin consultar la base.

## Requisitos

- Python 3.10+
- Credenciales AWS con `dynamodb:Query` sobre la tabla de eventos y **`s3:PutObject`** en el bucket de modelos (ver [aws-deploy-guide.md](../infrastructure/aws-deploy-guide.md) §8.2).
- Acceso de red a PostgreSQL (RDS o el host que indique `DB_URL`) y usuario con **lectura** sobre `restaurants`.

## Variables de entorno

| Variable | Descripción |
|----------|-------------|
| `AWS_REGION` | Región (ej. `us-east-1`) |
| `EVENTS_TABLE` | Tabla de eventos (ej. `menudigital-events`) |
| `RECOMMENDATIONS_MODEL_S3_BUCKET` | Bucket de modelos (obligatorio) |
| `RECOMMENDATIONS_MODEL_S3_KEY_PATTERN` | Patrón de clave con el literal `{tenantId}` (por defecto `recommendations/{tenantId}/model.json`) |
| `DB_URL` | JDBC como Quarkus: `jdbc:postgresql://host:5432/menudigital` (también acepta URL sin prefijo `jdbc:`) |
| `DB_USER` / `DB_PASS` | Usuario y contraseña (omitibles si usas `DB_SECRET_ARN` con usuario/clave en el JSON) |
| `DB_SECRET_ARN` | (Opcional) ARN en AWS Secrets Manager; JSON con `username`/`password` (formato RDS). Si no hay `DB_URL`, pueden ir `host`, `port`, `dbname` en el mismo JSON |
| `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB` | Alternativa si no usas `DB_URL` (requieren usuario vía `DB_USER` o `POSTGRES_USER`) |
| `TENANT_IDS` | Opcional: lista de UUIDs separada por comas; si está definida, **no** se consulta PostgreSQL |
| `DYNAMODB_PK_ATTR` / `DYNAMODB_SK_ATTR` | Opcional: nombres HASH y RANGE (por defecto `PK` y `SK`) |

## Uso local o en EC2

Desde el directorio `ml-training`:

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

**Cron** (la API cachea en memoria por tenant tras la primera lectura correcta; si **actualizas** el JSON de un tenant ya cacheado, hace falta **reiniciar** la API o vaciar instancias para ver el nuevo fichero):

```cron
15 4 * * * cd /opt/menudigital/ml-training && . .venv/bin/activate && AWS_REGION=us-east-1 DB_URL=jdbc:postgresql://... EVENTS_TABLE=menudigital-events DB_USER=... DB_PASS=... RECOMMENDATIONS_MODEL_S3_BUCKET=... python3 train_upload_model.py >> /var/log/menudigital-model.log 2>&1
```

En la misma VPC que RDS, `DB_URL` debe apuntar al endpoint del clúster. Si la URL JDBC incluye `?sslmode=require`, el script lo pasa a `psycopg2`.

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

- El backend solo usa `item_popularity` para ordenar sugerencias entre ítems disponibles; sin fichero o sin datos se mantiene el comportamiento aleatorio.
- IAM de la API: `s3:GetObject` sobre `arn:...:bucket/nombre/*` o al menos sobre las claves que coincidan con el patrón.
- El rol/usuario del job ETL necesita `rds:Connect` / seguridad de red hacia PostgreSQL además de DynamoDB y S3.
