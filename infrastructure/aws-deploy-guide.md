# Guía de despliegue en AWS (MenuDigital / MenuQR)

Si buscas una guía **paso a paso para novatos** (consola, orden de tareas, checklist), usa **[aws-deploy-novatos.md](./aws-deploy-novatos.md)**.

Esta guía describe cómo desplegar el stack en AWS de forma coherente con el código actual (Quarkus, PostgreSQL, DynamoDB, S3, frontends estáticos). Las sugerencias del carrito se calculan en el mismo Quarkus. Complementa el esquema de tablas en [dynamo-tables.md](./dynamo-tables.md).

## 1. Arquitectura de referencia (objetivo producción)

Diseño alineado con **multi-AZ**, **API en Auto Scaling Group**, **worker ETL/ML aparte** y **S3 separado para modelos** (el código ya soporta bucket de modelo vía `RECOMMENDATIONS_MODEL_S3_*`).

```
                    Route 53
                        │
    ┌───────────────────┼───────────────────┐
    │                   ▼                   │
    │   S3 (SPA menú)   │   S3 (SPA admin)  │   … fuera o dentro de VPC según CloudFront
    └───────────────────┴───────────────────┘

    Internet ──► IGW ──► ALB (subredes públicas, 80/443 + ACM)
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
     ASG: EC2 API (AZ-a)      ASG: EC2 API (AZ-b)
     Docker: nginx+Quarkus    (misma Launch Template / user-data)
            │                       │
            └───────────┬───────────┘
                        ▼
              RDS PostgreSQL 15 Multi-AZ (privado)

     EC2 ETL + ML (privado, típ. una AZ al inicio)
            │ cron: entrenamiento / subida de modelo
            ▼
     DynamoDB (eventos) ◄── Gateway VPC Endpoint
     S3 imágenes / assets          ◄── Gateway VPC Endpoint
     S3 modelos ML                 ◄── Gateway VPC Endpoint (mismo tipo; bucket distinto)

Las instancias **API** leen el JSON de popularidad por tenant desde **S3 modelos** bajo demanda (`RecommendationModelLoader`).
```

**Capas:**

| Capa | Componentes |
|------|-------------|
| **Entrada** | Route 53, ALB (HTTPS con ACM), opcional WAF. |
| **API** | **Auto Scaling Group** (ej. min 1 / deseado 1 / max 2) con **misma** AMI/Launch Template; target group en puerto 80 → nginx → Quarkus. |
| **Datos transaccionales** | RDS Multi-AZ; security group solo desde SG de las EC2 de API. |
| **Analítica** | DynamoDB; las API escriben eventos; el worker ETL puede leer eventos para entrenar y subir modelos a S3. |
| **Objetos** | **Bucket S3** para imágenes del menú (`S3_BUCKET`); **otro bucket** (recomendado) para **artefactos ML** (`RECOMMENDATIONS_MODEL_S3_*`); buckets para builds de SPA. |
| **Batch / ML** | **EC2 dedicada** (no en el ASG) para cron de [entrenamiento](./ml-segmentation/README.md) y subida del artefacto al bucket de modelos. |

**Qué corre en cada instancia del ASG (ver `docker-compose.prod.yml`):**

- **nginx** (80 hacia el ALB) y **backend** Quarkus (8080 interno; recomendaciones + carga opcional de modelo desde S3).

Los frontends **admin** y **menu** se publican en **S3** (idealmente con **CloudFront**). `VITE_API_URL` apunta al dominio del ALB.

## 2. Prerrequisitos

- Cuenta AWS, región elegida (ej. `us-east-1`).
- AWS CLI v2 configurado (para crear recursos o automatizar).
- Dominio (opcional pero recomendable para HTTPS con ACM).
- Claves JWT de producción: generar `privateKey.pem` / `publicKey.pem` **solo para prod** y montarlas en el contenedor (no commitear secretos).

## 3. Red (VPC)

| Recurso | CIDR / notas |
|--------|----------------|
| VPC | `10.0.0.0/16` |
| Subred pública AZ-a | `10.0.1.0/24` (ALB) |
| Subred pública AZ-b | `10.0.2.0/24` |
| Subred privada AZ-a | `10.0.3.0/24` (EC2, RDS) |
| Subred privada AZ-b | `10.0.4.0/24` |
| Internet Gateway | Adjunto a la VPC; rutas desde subredes públicas |
| NAT Gateway (recomendado) | En subred pública; rutas `0.0.0.0/0` desde subredes **privadas** hacia NAT para que EC2 descargue imágenes Docker y parches sin IP pública |

**A considerar:** si las instancias EC2 están **solo en subred privada** (recomendado), necesitán **NAT Gateway** para `docker pull` desde internet y/o **VPC endpoints** para reducir tráfico y coste hacia servicios AWS.

### 3.1 VPC endpoints (Gateway) — S3 y DynamoDB

Para que las instancias en **subred privada** hablen con **S3** y **DynamoDB** sin enrutar ese tráfico por el NAT:

1. **VPC** → **Endpoints** → **Create endpoint**.
2. Tipo **Gateway** para **`com.amazonaws.<region>.s3`** y **`com.amazonaws.<region>.dynamodb`**.
3. Asocia las **tablas de rutas** de las subredes **privadas** donde están API, ETL y RDS clients (normalmente las mismas rutas que usan las EC2 privadas).

Efecto: `GetObject`/`PutObject` a S3 y llamadas a Dynamo desde el SDK **usan el endpoint** (sin cargo por hora en Gateway; solo datos). El NAT sigue siendo útil para **ECR**, **apt/yum**, **Git**, etc., a menos que añadas **interface endpoints** para ECR (opcional, de pago).

## 4. Security groups

| SG | Entrada |
|----|---------|
| `sg-alb` | `80`, `443` desde `0.0.0.0/0` (restringir admin por IP si aplica) |
| `sg-api` (antes sg-ec2) | `80` **solo** desde `sg-alb` — lo llevan todas las instancias del **ASG** de la API |
| `sg-rds` | `5432` **solo** desde `sg-api` |
| `sg-etl` (worker ETL/ML) | Sin entrada desde internet. Opcional: **SSH** solo desde bastión o usar **SSM** sin abrir 22. Salida por defecto (NAT) para pip/git si hace falta |

No exponer el puerto 8080 de Quarkus a Internet; solo el ALB → nginx:80.

**RDS:** si en el futuro el ETL lee PostgreSQL, añade regla en `sg-rds` desde `sg-etl` (puerto 5432).

## 5. RDS PostgreSQL

- Motor: **PostgreSQL 15**, misma familia que en local/Docker.
- **Multi-AZ** para failover automático (típico ~1–2 minutos).
- Subredes privadas, asociado a `sg-rds`.
- Crear base `menudigital` y usuario con permisos acotados.
- **Flyway** ejecuta migraciones al arrancar Quarkus (`migrate-at-start=true`): no hace falta script manual si el `DB_URL` apunta al RDS y la base está vacía o al día.

Cadena JDBC ejemplo:

```text
jdbc:postgresql://<rds-endpoint>:5432/menudigital
```

## 6. DynamoDB

Crear las tablas según [dynamo-tables.md](./dynamo-tables.md):

- `menuqr-events` (solo PK/SK; sin LSI ni GSI).

Si teníais un LSI, GSI antiguos o un esquema distinto, hay que **recrear** `menuqr-events` (o nueva tabla + migración) para alinear el esquema.

Modo de facturación: **PAY_PER_REQUEST** (on-demand) suele bastar al inicio.

**IAM en EC2:** la política debe permitir al menos `dynamodb:PutItem`, `dynamodb:Query`, `dynamodb:GetItem` sobre:

- `arn:aws:dynamodb:<region>:<account>:table/menuqr-events`

En **producción**, no hace falta `DYNAMO_ENDPOINT` ni claves estáticas: el SDK usa **IAM instance profile** si `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` no están definidos para S3/Dynamo (el código ya usa `DefaultCredentialsProvider` cuando faltan claves).

**A considerar (evolución):** TTL en items de eventos, paginación en queries para tenants muy grandes, agregados asíncronos mediante **otro proceso en EC2** (cola en disco, cron más frecuente, o worker dedicado), sin usar Lambda.

## 7. S3

### Bucket de imágenes y assets de aplicación

- Nombre único global, ej. `menudigital-images-<account-id>`.
- Política de lectura pública **solo en objetos** si el front muestra URLs directas; valorar **CloudFront + OAI** para no abrir el bucket al mundo.
- CORS: permitir `GET` (y `PUT` si subís desde el navegador) desde el origen de vuestros SPAs y/o API.

### Buckets de SPAs

- `menudigital-admin`, `menudigital-menu` (nombres de ejemplo).
- Subir artefactos de build:

```bash
cd frontend/admin && npm ci && npm run build
aws s3 sync dist s3://menudigital-admin --delete

cd ../menu && npm ci && npm run build
aws s3 sync dist s3://menudigital-menu --delete
```

Variables de build (ej. en CI):

- `VITE_API_URL=https://api.tudominio.com` (o `https://tudominio.com` si la API va en el mismo host bajo `/api`).

**Recomendación:** servir SPAs detrás de **CloudFront** con HTTPS (certificado ACM en `us-east-1` si usáis CloudFront).

### Bucket de modelos ML (recomendado en producción)

- Bucket **dedicado**, ej. `menudigital-models-<account-id>`, para artefactos entrenados (ONNX, etc.).
- El **worker ETL/ML** sube un JSON por tenant (`PutObject`); las instancias **API** necesitan **`GetObject`** sobre el prefijo/patrón de claves (p. ej. `recommendations/*`).
- Así separás IAM (el batch puede escribir modelos; la API no debe poder sobrescribirlos salvo que lo queráis).

## 8. IAM — roles separados (API vs ETL/ML)

### 8.1 Rol para instancias del ASG (`menudigital-api-ec2`)

Incluye imágenes, DynamoDB, **lectura** del modelo y, si usáis `DB_SECRET_ARN`, **lectura del secreto** de RDS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::menudigital-images-<account-id>/*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::menudigital-models-<account-id>/*"
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:GetItem"],
      "Resource": "arn:aws:dynamodb:<region>:<account>:table/menuqr-events"
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:<nombre-secreto-rds-*"
    }
  ]
}
```

Añadí **`ecr:GetAuthorizationToken`** y **`ecr:BatchGetImage`** + permisos de capa si tiráis de ECR sin endpoint; o mantened NAT para `docker pull`.

### 8.2 Rol para EC2 ETL + ML (`menudigital-etl-ec2`)

Lectura de eventos en DynamoDB y **escritura** de modelos en S3:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::menudigital-models-<account-id>/*"
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:Query", "dynamodb:Scan", "dynamodb:GetItem", "dynamodb:PutItem"],
      "Resource": "arn:aws:dynamodb:<region>:<account>:table/menuqr-events"
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:<nombre-secreto-rds-*"
    }
  ]
}
```

Si el ETL consulta **RDS**, añadí credenciales vía Secrets Manager y `secretsmanager:GetSecretValue` + conectividad `sg-etl` → `sg-rds`.

Ajustad ARNs y KMS si usáis cifrado en bucket.

## 9. Imagen del backend, ECR y Auto Scaling Group

### 9.1 Flujo recomendado: build local o CI + ECR

En un entorno de build (CI o máquina local):

```bash
cd backend
mvn -DskipTests package
docker build -f src/main/docker/Dockerfile.jvm -t menudigital-backend:latest .
```

Subir la imagen a **Amazon ECR** y en cada EC2 hacer `docker pull` de ese tag.

### 9.2 Sin ECR: build en la instancia vía user-data (Launch Template)

Si **no** usás ECR, podés poner en el **user data** de la plantilla un script que:

1. Instale **Docker** y **Compose v2** (Amazon Linux: `yum install -y docker git`; el plugin `docker-compose-plugin` si está en repos, o binario desde GitHub en AL2 — ver script en `launch-template/`).
2. Clone el repo (**Git**; repo privado: token vía **SSM Parameter Store** o deploy key, no hardcodear en claro).
3. Secretos: el user-data escribe `.env` desde la sección **CONFIG** del script (completá variables ahí). Genera `privateKey.pem` / `publicKey.pem` si no existen; en producción podés reemplazarlas por claves propias y reiniciar el contenedor del backend.
4. Ejecute `docker build -f backend/src/main/docker/Dockerfile.jvm -t menudigital-backend:latest backend/` (el **Maven** corre **dentro** del `Dockerfile.jvm`, no hace falta instalar Maven en el host).
5. Levante `docker compose -f docker-compose.prod.yml up -d`.

En el repo hay un ejemplo listo para adaptar: [`infrastructure/launch-template/user-data-al2023-build-no-ecr.sh`](./launch-template/user-data-al2023-build-no-ecr.sh).

**Implicaciones:** el **primer arranque** de cada instancia nueva es **lento** (descarga de capas base + compilación Quarkus). En el **ASG** subí el **health check grace period** a **600–900 s** (o más en `t3.small`). Cada **nueva** instancia repetirá el build salvo que uses una **AMI golden** generada con Packer u otra herramienta.

**IAM sin ECR:** no hace falta `ecr:*` para este flujo; sí **S3** si copiás secretos, y permisos de **SSM** si leés parámetros.

**Contenido mínimo en el servidor** (junto al compose):

- `docker-compose.prod.yml` (o copia ajustada).
- `privateKey.pem`, `publicKey.pem` (permisos restrictivos).
- Archivo `.env` o parámetros inyectados (ver siguiente sección).

**User-data (esquema) — Launch Template del ASG:**

1. Instalar Docker y plugin Compose v2.
2. Autenticar ECR (`aws ecr get-login-password` …) si usáis registry privado.
3. `docker compose pull && docker compose up -d`.

**Auto Scaling Group (recomendado en lugar de “2 EC2 fijas”):**

- **Launch Template:** AMI (Amazon Linux 2023), tipo `t3.small`, `sg-api`, subredes **privadas** en **2 AZ**, disco EBS, **IAM instance profile** = rol API.
- **ASG:** min **1**, deseado **1**, max **2** (o según carga); políticas de escala opcionales (CPU, requests ALB).
- Adjuntar el ASG al **target group** del ALB; health check **GET** `/q/health`.

**EC2 ETL + ML (fuera del ASG):** misma VPC, subred privada, **rol ETL**, sin registro en el ALB. Desplegar ahí el repo o solo `infrastructure/ml-segmentation` + scripts de entrenamiento; **cron** diario/semanal.

### 9.3 ECS Fargate + ALB (Terraform)

El módulo Terraform puede desplegar la API en **ECS Fargate** con un **ALB** (listener HTTP 80 → contenedor 8080), en lugar de (o además de) la EC2 del ASG.

1. **Secrets Manager — JWT (obligatorio con Fargate):** dos secretos de tipo cadena con el **PEM en texto** (no JSON), uno para la clave pública y otro para la privada de firma (los mismos que usarías como `publicKey.pem` / `privateKey.pem` en el servidor).
2. **tfvars:** `enable_backend_fargate = true`, `jwt_public_pem_secret_arn` y `jwt_private_pem_secret_arn` con los ARN completos. Para migrar desde EC2: `enable_backend_ec2 = false` cuando el servicio Fargate esté estable.
3. **Imagen:** por defecto Terraform crea **ECR** `<vpc-name>-backend`; construí y subí la imagen (misma `Dockerfile.jvm` que en la sección 9.1). El `entrypoint.sh` del contenedor lee `JWT_PUBLIC_PEM` / `JWT_PRIVATE_PEM` (inyectadas por ECS desde Secrets Manager) y genera los ficheros que Quarkus espera.
4. **Push y despliegue:** `docker tag … && docker push <ecr_url>:latest` y luego **ECS → servicio → actualizar** (nueva revisión de task) o `aws ecs update-service --force-new-deployment`.
5. **Salidas Terraform:** `backend_fargate_alb_dns_name`, `backend_fargate_ecr_repository_url`, `backend_fargate_ecs_cluster_name`.
6. **CPU/memoria y arquitectura:** `backend_fargate_cpu`, `backend_fargate_memory` (pares válidos según la [tabla Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html)), `backend_fargate_cpu_architecture` (`X86_64` o `ARM64`, alineado con el build de la imagen).
7. **HTTPS:** el ALB de este stack solo expone **80**; podés añadir listener 443 con certificado **ACM** en una iteración posterior o delante un CloudFront.
8. **KMS (CMK propia):** si los secretos JWT en Secrets Manager o el secreto maestro de RDS usan una **clave gestionada por el cliente**, rellená `backend_fargate_kms_customer_key_arns` con el/los ARN de esas CMK. Terraform concede `kms:Decrypt` y `kms:DescribeKey` al **rol de ejecución** ECS (para inyectar los PEM JWT) y al **rol de task** (para que la app lea el secreto de RDS). Si además cifráis el repositorio **ECR** con CMK, definí `backend_ecr_repository_kms_key_arn` (el repositorio pasa a `encryption_type = KMS` y el rol de ejecución incluye esa clave para el `pull` de la imagen). Los outputs `backend_fargate_ecs_execution_role_arn` y `backend_fargate_ecs_task_role_arn` sirven para añadir esos principals en la **key policy** de la CMK si no usáis el delegado amplio de la cuenta.

El rol de la **task** incluye S3 (imágenes + modelos), DynamoDB sobre la tabla de eventos y lectura del secreto maestro de RDS (la app resuelve credenciales vía `DB_SECRET_ARN` como en EC2).

## 10. Application Load Balancer

- Con **EC2 + nginx** delante: ALB **internet-facing** en subredes públicas; target group HTTP **80** hacia las instancias (nginx).
- Con **Fargate (Terraform, sección 9.3):** el ALB creado por Terraform apunta directamente al **contenedor Quarkus en el puerto 8080** (sin nginx en ese path).
- Health check: ruta **`/q/health`** o **`/q/health/ready`** (en el target group de Fargate del Terraform se usa **`/q/health/ready`**), código 200, intervalos razonables.
- **HTTPS (443):** certificado en **ACM**, listener 443 → target group 80 (o terminación SSL en nginx si gestionáis cert allí).

**Cabeceras:** Quarkus y proxies suelen necesitar confianza en `X-Forwarded-*` si generáis URLs absolutas; para este proyecto la mayoría de rutas son relativas vía ALB.

## 11. Variables de entorno en producción

Definid al menos (nombres alineados con `application.properties` y `docker-compose.prod.yml`):

| Variable | Descripción |
|----------|-------------|
| `DB_URL` | JDBC a RDS |
| `DB_USER` / `DB_PASS` | Credenciales RDS (omitibles en EC2 si usas `DB_SECRET_ARN`) |
| `DB_SECRET_ARN` | (Opcional) ARN del secreto en **Secrets Manager** con JSON tipo RDS (`username`, `password`; opcionalmente `host`, `port`, `dbname`). La API Quarkus y el job `train_upload_model.py` lo leen en tiempo de ejecución. |
| `DB_SECRET_CACHE_SECONDS` | (Opcional) Segundos de caché en la API tras leer el secreto (por defecto `300`). |
| `AWS_REGION` | Región (ej. `us-east-1`) |
| `S3_BUCKET` | Bucket de **imágenes** del menú (distinto del de modelos en prod) |
| `RECOMMENDATIONS_MODEL_S3_BUCKET` | Bucket de **modelos** (puede ser `menudigital-models-…`) |
| `DYNAMO_TABLE` | Tabla de eventos (ej. `menuqr-events`) |
| *(no definir)* `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Preferir IAM role en EC2 |
| *(no definir)* `DYNAMO_ENDPOINT`, `S3_ENDPOINT` | Vacío en AWS real (servicio gestionado) |
| `S3_PUBLIC_URL` | URL pública base para enlazar imágenes (CloudFront o `https://bucket.s3...`) |
| `RECOMMENDATIONS_MODEL_S3_KEY_PATTERN` | Patrón de clave del fichero **binario MREC** (`.bin`) con el literal `{tenantId}` (ej. `recommendations/{tenantId}/model.bin`); por defecto en `docker-compose.prod.yml` |

**Secretos:** el código soporta **AWS Secrets Manager** vía `DB_SECRET_ARN` (sin volcar la contraseña a `.env`). El rol IAM de la instancia API y el del worker ETL deben incluir `secretsmanager:GetSecretValue` sobre ese ARN (o un `resource` con comodín acotado). Alternativa clásica: Parameter Store / `ExecStartPre` que escriba `.env` en disco (cifrar volumen o evitar persistencia en claro).

**JWT:** rotación de claves implica redeploy coordinado; documentar el procedimiento.

## 12. Recomendaciones del menú

El endpoint `POST /api/menu/{slug}/recommendations` prioriza ítems con más vistas si existe el artefacto **MREC** (`.bin`) en S3 para el **tenant** del menú (`RECOMMENDATIONS_MODEL_S3_BUCKET` + patrón con `{tenantId}`). El job también sube **joblib** (mismo prefijo, extensión `.joblib`) para uso en Python. Si no hay `.bin` o está vacío, las sugerencias siguen siendo aleatorias.

## 13. Entrenamiento del modelo en EC2 o Lambda (opcional)

El código vive en [ml-training/](../ml-training/): **`train_upload_model.py`** (CLI), **`recommendations_etl.py`** (lógica compartida) y Lambdas **`orchestrator_lambda`** / **`worker_lambda`**.

- **EC2 + cron**: ejecutar el CLI con las variables `DB_*`, Dynamo y S3 (rol con `dynamodb:Query`, `s3:PutObject`, y si aplica `secretsmanager:GetSecretValue`).
- **Lambda fan-out** (`enable_recommendations_fanout = true` en Terraform): orquestador en VPC (RDS + cola SQS) y workers sin VPC (Dynamo + bucket ML). Antes de `apply`, generar `ml-training/lambda_dist/*` con `scripts/build_lambda_dists.sh` (en ARM/macOS usar imagen `sam/build-python3.12`, ver README de ml-training).
- Instrucciones detalladas: [ml-training/README.md](../ml-training/README.md).
- **No** usar EventBridge hacia Lambdas distintas del diseño anterior si ya tenéis cron en EC2; elegid un modo u otro para no duplicar entrenamientos.

## 14. Route 53 y DNS

- Registro **A/AAAA alias** al nombre DNS del ALB para el host de la API (ej. `api.tudominio.com`).
- Subdominios para admin/menú apuntando a CloudFront o a los endpoints S3 website, según elegís.

## 15. Verificación post-despliegue

1. `curl -sS https://<alb-o-dominio>/q/health` → JSON con estado UP.
2. Registro y login en admin (JWT).
3. Menú público: carga y envío de eventos (`POST /api/menu/{slug}/events`) sin errores en DynamoDB (CloudWatch / métricas).
4. Subida de imagen desde el panel y comprobación en S3 + URL pública.
5. Carrito con ítems: `POST /api/menu/{slug}/recommendations` devuelve sugerencias desde el mismo backend.

## 16. Mejoras de arquitectura recomendadas (resumen)

| Tema | Recomendación |
|------|----------------|
| Alta disponibilidad API | **ASG** min 1 / max 2 en 2 AZ, health check ALB a `/q/health` |
| VPC endpoints | Gateway **S3** + **DynamoDB** en rutas de subredes privadas (menos NAT) |
| Worker batch | **EC2 ETL/ML** aparte del ASG; rol IAM distinto (escribe modelos, lee Dynamo) |
| Secretos | Parameter Store / Secrets Manager, no contraseñas en git |
| HTTPS | ACM + ALB (y CloudFront para estáticos) |
| Imágenes | CloudFront delante de S3, políticas de bucket restrictivas |
| DynamoDB | TTL opcional; paginación en lecturas pesadas; unificar nombres de tabla vía env (hecho en `application.properties`) |
| Observabilidad | CloudWatch Logs para contenedores, alarmas ALB 5xx y latencia RDS |
| Backups | RDS backup automático + ventana de mantenimiento |
| WAF | Opcional delante del ALB si la API es pública |

## 17. Coste orientativo (us-east-1, orden de magnitud)

Los importes varían con tráfico y tamaños; son una referencia inicial:

| Servicio | Notas | ~USD/mes |
|----------|--------|----------|
| EC2 ×2 | `t3.small` | ~30 |
| RDS | `db.t3.micro` Multi-AZ | ~30 |
| ALB | Hora + LCU | ~20 |
| DynamoDB | On-demand, bajo volumen | ~5 |
| S3 + transferencia | Bajo uso | ~5 |
| NAT Gateway | Si usáis NAT en 2 AZ | +30–70 (revisar) |
| **Total orientativo** | Sin NAT / con NAT | **~90** / **~120+** |

## 18. Documentación relacionada

- [aws-setup.md](./aws-setup.md) — índice breve y enlace a esta guía.
- [dynamo-tables.md](./dynamo-tables.md) — esquema DynamoDB.
- [ml-segmentation/README.md](./ml-segmentation/README.md) — entrenamiento y subida del modelo (cron + Python).
