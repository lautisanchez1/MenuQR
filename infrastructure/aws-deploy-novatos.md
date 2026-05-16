# Desplegar MenuQR en AWS — guía paso a paso (principiantes)

Esta guía asume que **conoces lo básico de terminal** (carpetas, pegar comandos) pero **no** que ya sepas AWS. Al final tendrás la API en internet, base de datos, analítica en DynamoDB, imágenes en S3 y los frontends publicados.

Para detalles técnicos extra, ver también [aws-deploy-guide.md](./aws-deploy-guide.md) y [dynamo-tables.md](./dynamo-tables.md).

---

## Antes de empezar: conceptos en 30 segundos

| Término | Qué es |
|--------|--------|
| **Región** | Un “datacenter” de AWS (ej. `us-east-1` Virginia). Elige **una** y crea todo ahí. |
| **VPC** | Tu red privada virtual: subredes, firewalls (security groups), quién habla con quién. |
| **EC2** | Una máquina virtual (servidor) donde correrá Docker con tu backend. |
| **RDS** | Base PostgreSQL gestionada (no instalas tú el motor). |
| **ALB** | Balanceador que recibe el tráfico de internet y lo reparte a tus EC2. |
| **S3** | Almacenamiento: imágenes del menú, SPAs y (recomendado) **otro bucket** solo para modelos ML. |
| **ASG** | Auto Scaling Group: varias EC2 de API con la misma plantilla; el ALB reparte entre ellas. |
| **DynamoDB** | Base NoSQL para **eventos de analítica** (vistas del menú, etc.). |
| **IAM** | Permisos: qué puede hacer cada recurso (ej. la EC2 leyendo S3). |

---

## Paso 0 — Cuenta, región y herramientas

1. Crea una cuenta en [aws.amazon.com](https://aws.amazon.com) y activa facturación.
2. En la consola AWS, arriba a la derecha, elige una **región** (recomendado: **N. Virginia `us-east-1`** para seguir esta guía tal cual).
3. Activa una **alarma de facturación** (Billing → Budgets) para no llevar sorpresas.
4. En tu PC instala:
   - **Docker** (para construir imágenes).
   - **AWS CLI v2** ([instrucciones oficiales](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)).
5. Configura la CLI (sustituye tus claves de usuario IAM con acceso programático):

   ```bash
   aws configure
   ```

   Te pedirá `Access Key`, `Secret`, región (`us-east-1`) y formato de salida (`json`).

**Importante:** el usuario IAM que uses debe tener permisos para crear VPC, EC2, RDS, S3, DynamoDB, IAM (rol de instancia), ELB, etc. Para aprender, a veces se usa `AdministratorAccess`; en producción se acota.

---

## Paso 1 — Red (VPC) para “producción razonable”

Objetivo: subredes **públicas** (para el ALB) y **privadas** (para EC2 y RDS), con salida a internet para que EC2 pueda hacer `docker pull` (NAT Gateway).

**Opción fácil (asistente de la consola):**

1. Consola AWS → busca **VPC** → **Create VPC**.
2. Elige **VPC and more**.
3. Marca: **2 Availability Zones**, **2 public subnets**, **2 private subnets**, **1 NAT Gateway** (o 1 por AZ si quieres más resiliencia, sube coste).
4. Nombre algo como `menudigital-vpc` y crea.
5. Anota los IDs de las **subredes privadas** y **públicas** (los usarás en RDS, ALB y EC2).

Si no quieres pagar NAT al principio, puedes poner la primera EC2 en subred **pública** solo para **pruebas** (menos seguro); esta guía asume **EC2 en privada + NAT** como en [aws-deploy-guide.md](./aws-deploy-guide.md).

### Paso 1b — Endpoints de VPC (opcional pero recomendado)

Para que S3 y DynamoDB no salgan por el **NAT** (ahorro y alineado con arquitectura objetivo):

1. **VPC** → **Endpoints** → crear **Gateway** para `com.amazonaws.us-east-1.s3` y `com.amazonaws.us-east-1.dynamodb` (cambia la región si no es `us-east-1`).
2. Asocia las **route tables** de tus subredes **privadas**.

Detalle: [aws-deploy-guide.md §3.1](./aws-deploy-guide.md#31-vpc-endpoints-gateway--s3-y-dynamodb).

---

## Paso 2 — Security groups (firewalls)

Crea **tres** security groups en la misma VPC (nombre sugerido entre paréntesis):

### 2.1 `sg-alb` (ALB)

- **Inbound:** tipo **HTTP**, puerto **80**, origen **0.0.0.0/0**.  
- Opcional: **HTTPS 443** cuando tengas certificado.
- **Outbound:** por defecto (todo).

### 2.2 `sg-api` (instancias del ASG / API con Docker)

- **Inbound:** puerto **80**, origen el **security group del ALB** (`sg-alb`), no “cualquiera”.
- **Outbound:** por defecto.

### 2.3 `sg-rds` (PostgreSQL)

- **Inbound:** tipo **PostgreSQL**, puerto **5432**, origen **`sg-api`** (solo las instancias de la API).
- **Outbound:** por defecto.

### 2.4 `sg-etl` (opcional — worker ETL / ML)

- **Inbound:** ninguna desde `0.0.0.0/0`. Para operar: **Session Manager** (IAM) o bastión.
- **Outbound:** por defecto (NAT para `pip`, etc.).

---

## Paso 3 — RDS PostgreSQL

1. Consola → **RDS** → **Create database**.
2. Motor: **PostgreSQL**, versión **15** (alineada con el proyecto).
3. Plantilla: **Production** o **Dev/Test** (más barato).
4. Identificador y credenciales: usuario y contraseña **fuertes**; guárdalos en un gestor de secretos.
5. **Instance configuration:** tamaño pequeño al inicio (ej. `db.t3.micro`).
6. **Storage:** por defecto está bien.
7. **Connectivity:** VPC creada, subredes **privadas**, **no** público.
8. **VPC security group:** elige **sg-rds**.
9. **Database name:** `menudigital` (o el que luego pongas en `DB_URL`).
10. Crea la base y espera a que el estado sea **Available**.
11. En la ficha del RDS copia el **endpoint** (algo como `menudigital.xxxx.us-east-1.rds.amazonaws.com`).

Tu JDBC será:

```text
jdbc:postgresql://TU_ENDPOINT:5432/menudigital
```

---

## Paso 4 — DynamoDB (analítica)

Las tablas deben coincidir con [dynamo-tables.md](./dynamo-tables.md). La forma más rápida es la **CLI** (en tu PC, con `aws configure` hecho).

### 4.1 Tabla `menudigital-events`

Ejecuta **un solo bloque** (puedes cambiar el nombre de tabla si quieres, pero luego usa el mismo en variables de entorno):

```bash
export AWS_REGION=us-east-1
export TABLE_EVENTS=menudigital-events

aws dynamodb create-table \
  --table-name "$TABLE_EVENTS" \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=PK,AttributeType=S \
    AttributeName=SK,AttributeType=S \
  --key-schema \
    AttributeName=PK,KeyType=HASH \
    AttributeName=SK,KeyType=RANGE \
  --region "$AWS_REGION"
```

Si la tabla ya existe, el comando fallará; en ese caso puedes ignorar el error. Si tenías un LSI o GSI antiguos y quieres alinear el esquema a solo PK/SK, recrea la tabla (o nueva tabla + migración).

---

## Paso 5 — S3 (imágenes y, opcional, frontends)

### 5.1 Bucket de imágenes

1. **S3** → **Create bucket**.
2. Nombre **único en el mundo** (ej. `menudigital-images-TU-ACCOUNT-ID`).
3. Región la misma que el resto.
4. **Block Public Access:** para que las imágenes del menú se vean en el navegador, muchas demos desactivan el bloqueo público y ponen una política de lectura; en producción es mejor **CloudFront**. Para empezar, sigue la política de ejemplo en [aws-deploy-guide.md §7](./aws-deploy-guide.md#7-s3) y configura **CORS** si subes desde el admin.

Anota el **nombre del bucket** → lo usarás en `S3_BUCKET`.

### 5.2 (Opcional) Buckets para el build del admin y del menú

Crea dos buckets (o uno con prefijos) para subir `dist/` de cada frontend después del build.

### 5.3 Bucket de modelos ML (recomendado)

1. Crea otro bucket, ej. `menudigital-models-TU-ACCOUNT-ID` (sin mezclar con imágenes).
2. El **worker ETL** subirá por tenant un binario **MREC** (`.bin`, lo lee la API) y un **joblib** (`.joblib`); la **API** necesita `GetObject` sobre el patrón `.bin` (`RECOMMENDATIONS_MODEL_S3_KEY_PATTERN` con `{tenantId}`).

---

## Paso 6 — Roles IAM (API y, opcional, ETL)

No uses claves de acceso largas en el `.env` en producción: **Instance profile** por tipo de máquina.

### 6.1 Rol para el ASG / API (`menudigital-api-ec2`)

Permite imágenes + DynamoDB + **lectura** del bucket de modelos. Copia el JSON de la guía técnica ([rol API — §8.1](./aws-deploy-guide.md)).

### 6.2 Rol para EC2 ETL/ML (`menudigital-etl-ec2`) — opcional

Para [ml-segmentation](./ml-segmentation/README.md) y scripts que **suban** el modelo a S3. JSON en la guía técnica ([§8.2](./aws-deploy-guide.md)).

Asocia **6.1** al **Launch Template** del ASG (o a la primera EC2 si aún no usás ASG).

---

## Paso 7 — Imagen Docker del backend

En tu máquina, en la carpeta del repo:

```bash
cd backend
mvn -DskipTests package
docker build -f src/main/docker/Dockerfile.jvm -t menudigital-backend:latest .
```

Subir a **ECR** (registro de contenedores de Amazon):

1. Consola **ECR** → **Create repository** → nombre `menudigital-backend` → privado.
2. Sigue los comandos **“View push commands”** que te muestra AWS (login, tag, push).  
   Al final tendrás una URI tipo:  
   `123456789012.dkr.ecr.us-east-1.amazonaws.com/menudigital-backend:latest`

---

## Paso 8 — Claves JWT de producción

En el servidor (o en tu PC antes de copiar), genera par de claves **solo para producción**:

```bash
openssl genrsa -out privateKey.pem 2048
openssl rsa -pubout -in privateKey.pem -out publicKey.pem
```

Cópialas a la carpeta donde estaré el `docker-compose.prod.yml` en la EC2 (mismos paths que en el compose: montados en el contenedor). **No las subas a Git.**

---

## Paso 9 — Lanzar la API: una EC2 o Auto Scaling Group

**Objetivo de arquitectura:** **ASG** con la misma plantilla en **2 AZ** (ver [aws-deploy-guide.md](./aws-deploy-guide.md) sección *Imagen del backend, ECR y Auto Scaling Group*).

### Orden si vas a usar ASG + ALB

1. Crea primero el **Target Group** del [Paso 11](#paso-11--application-load-balancer) (VPC, puerto **80**, health **`/q/health`**), **sin** registrar instancias manualmente.
2. Crea **Launch Template** y luego el **ASG** enlazado a ese Target Group (pasos abajo).
3. Crea el **ALB** y el **listener** (HTTP/HTTPS) que envíe tráfico a **ese mismo** Target Group.

Así las nuevas instancias del ASG se registran solas en el TG y el balanceador las enruta cuando esté listo.

### Opción A — Primera vez (una sola instancia)

1. **EC2** → **Launch instance**.
2. AMI **Amazon Linux 2023**, tipo **t3.small**, **sg-api**, subred **privada**, **IAM** = rol **API** (paso 6.1).
3. User-data: instalar Docker + Compose + `docker compose up` (como antes).

### Opción B — Producción (resumen)

- **Launch Template** = misma AMI, tipo, SG, IAM y user-data que la opción A.
- **ASG** = min **1**, deseado **1**, max **2**, **dos subredes privadas en AZ distintas**, adjunto al **Target Group** del ALB.
- Health check del ASG: tipo **ELB** cuando el TG está detrás de un ALB.

### Opción B — Paso a paso en la consola de AWS

#### B.1 Launch Template (plantilla de lanzamiento)

1. Consola **EC2** → menú izquierdo **Launch Templates** → **Create launch template**.
2. **Launch template name:** por ejemplo `menudigital-api-lt`.
3. **Template version description:** `v1` (o la que quieras).
4. **Application and OS Images (AMI):** busca **Amazon Linux 2023** (Kernel 6.1, 64-bit x86).
5. **Instance type:** `t3.small` (o superior si necesitás más RAM para Docker).
6. **Key pair:** opcional si vas a usar solo **Systems Manager Session Manager**; si querés SSH clásico, elegí un key pair.
7. **Network settings** → **Security groups:** elige **`sg-api`** (no hace falta fijar subred aquí; el ASG la elige).
8. **Storage:** volumen raíz **gp3**, por ejemplo **30 GiB** (Docker + imágenes ocupan espacio).
9. **Advanced details:**
   - **IAM instance profile:** rol **API** del paso 6.1 (`menudigital-api-ec2` o el nombre que hayas puesto).
   - **User data** (texto, **no** base64 en la consola; AWS lo codifica solo). Dos enfoques:
     - **Con ECR:** instalar Docker + Compose, `aws ecr get-login-password | docker login ...`, `docker compose pull && docker compose up -d` (y copiar `.env` + JWT desde S3 o SSM).
     - **Sin ECR:** instalar Docker + Compose + Git, **clonar el repo**, `docker build` del backend en la instancia (el `Dockerfile.jvm` ya ejecuta Maven dentro de la build) y `docker compose up -d`. Ejemplo completo en el repo: [`launch-template/user-data-al2023-build-no-ecr.sh`](./launch-template/user-data-al2023-build-no-ecr.sh). Subí el **health check grace period** del ASG a **600–900 s** porque el primer arranque es lento.

   Esquema mínimo (solo idea; preferí el script del repo si no usás ECR):

   ```bash
   #!/bin/bash
   set -e
   yum update -y
   yum install -y docker git
   systemctl enable --now docker
   yum install -y docker-compose-plugin || true  # en AL2 a veces falta; ver script completo en launch-template/
   mkdir -p /opt/menudigital && cd /opt/menudigital
   # Con ECR: login + docker compose pull/up
   # Sin ECR: git clone ... && docker build ... && docker compose up -d
   ```

   Ajustá el user-data a cómo vayas a inyectar **`.env`** (S3, SSM, etc.); el [Paso 10](#paso-10--archivo-env-y-docker-composeprodyml-en-el-servidor) describe el contenido del `.env`.

10. **Create launch template**.

#### B.2 Auto Scaling Group

1. **EC2** → **Auto Scaling Groups** → **Create Auto Scaling group**.
2. **Name:** por ejemplo `menudigital-api-asg`.
3. **Launch template:** seleccioná `menudigital-api-lt` y la **versión** (`Default` o `$Latest`).
4. **VPC:** tu VPC; **Availability Zones and subnets:** elegí **dos subredes privadas**, una por AZ (las mismas familia donde puede enrutar el ALB hacia instancias privadas).
5. **Load balancing** (importante):
   - Elegí **Attach to an existing load balancer**.
   - **Traffic receiving:** **Application Load Balancer** o **Network Load Balancer** según hayas creado (MenuQR usa **ALB**).
   - **Choose from your load balancer target groups:** seleccioná el **Target Group** creado en el Paso 11 (puerto 80).
6. **Health checks:**
   - Activá **ELB health checks** (así el ASG da de baja instancias que el ALB marca unhealthy).
   - **Health check grace period:** **180–300** s si solo hacés `docker pull` + `compose up` con imagen ya en ECR; **600–900** s (o más) si en el user-data **construís la imagen en la instancia** sin ECR (ver script en `infrastructure/launch-template/`).
7. **Group size:**
   - **Desired capacity:** `1`
   - **Min:** `1`
   - **Max:** `2` (o más si definís políticas de escala después).
8. **Scaling policies** (opcional en el primer despliegue): podés dejar sin políticas dinámicas y escalar a mano cambiando *desired*, o añadir **Target tracking** sobre CPU del ASG.
9. **Create Auto Scaling group**.

Esperá unos minutos: deberían lanzarse instancias, registrarse en el Target Group y pasar a **healthy** cuando nginx responda en `/q/health` (tras el grace period).

#### B.3 Comprobaciones rápidas

- **EC2** → **Instances:** instancias con nombre/lanzamiento desde el template; sin IP pública si están solo en subred privada.
- **EC2** → **Target Groups** → tu grupo → pestaña **Targets:** estado **healthy**.
- Navegador o `curl` al DNS del ALB: `/q/health`.

### Opción B — Equivalente con AWS CLI (referencia)

Sustituí IDs y ARNs por los tuyos (`subnet-xxx`, `lt-xxx`, `arn:aws:elasticloadbalancing:...:targetgroup/...`).

```bash
# 1) Launch template (versión 1) — el user-data debe ir en base64 en CLI
#    (generar con: base64 -w0 user-data.sh > user-data.b64 y pegar en --user-data file://...)
aws ec2 create-launch-template \
  --launch-template-name menudigital-api-lt \
  --version-description v1 \
  --launch-template-data '{
    "ImageId": "ami-XXXXXXXX",
    "InstanceType": "t3.small",
    "SecurityGroupIds": ["sg-api"],
    "IamInstanceProfile": {"Name": "menudigital-api-ec2-profile"},
    "UserData": "BASE64_DEL_SCRIPT"
  }'

# 2) Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name menudigital-api-asg \
  --launch-template LaunchTemplateName=menudigital-api-lt,Version='$Latest' \
  --min-size 1 --max-size 2 --desired-capacity 1 \
  --vpc-zone-identifier "subnet-AZ1-privada,subnet-AZ2-privada" \
  --target-group-arns "arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/menudigital-tg/xxxx" \
  --health-check-type ELB \
  --health-check-grace-period 300
```

Para **AMI ID** de Amazon Linux 2023 en tu región:

```bash
aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64 \
  --query 'Parameters[0].Value' --output text
```

**Conectar:** Session Manager (**Systems Manager**) si la instancia tiene el agente y rol con `AmazonSSMManagedInstanceCore`, o bastión + SSH.

En la instancia: Docker + Compose ([guía Docker AL2023](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-getting-started-choose-installation.html#serverless-getting-started-install-docker)).

---

## Paso 10 — Archivo `.env` y `docker-compose.prod.yml` en el servidor

En la EC2, en la carpeta donde tengas `docker-compose.prod.yml` y las claves JWT:

1. Copia `docker-compose.prod.yml` del repo (y ajusta si las rutas de contexto build apuntan a ECR en lugar de `build:` local; lo habitual es **solo** `image: ...ecr.../menudigital-backend:latest` sin `build` en producción).
2. Crea `.env` (permisos restrictivos):

```bash
DB_URL=jdbc:postgresql://TU_ENDPOINT_RDS:5432/menudigital
DB_USER=EL_USUARIO_RDS
DB_PASS=LA_CONTRASEÑA_RDS
AWS_REGION=us-east-1
S3_BUCKET=menudigital-images-TU-CUENTA
DYNAMO_TABLE=menudigital-events
# Opcional: bucket solo modelos (recomendado ≠ imágenes)
# RECOMMENDATIONS_MODEL_S3_BUCKET=menudigital-models-TU-CUENTA
# RECOMMENDATIONS_MODEL_S3_KEY_PATTERN=recommendations/{tenantId}/model.bin
S3_PUBLIC_URL=https://TU-BUCKET.s3.us-east-1.amazonaws.com
```

**No** definas `AWS_ACCESS_KEY_ID` ni `AWS_SECRET_ACCESS_KEY` si usas el rol IAM (recomendado).  
**No** definas `DYNAMO_ENDPOINT` ni `S3_ENDPOINT` en AWS real (deben quedar vacíos para usar el servicio gestionado).

3. Autentica ECR y levanta:

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
docker compose -f docker-compose.prod.yml --env-file .env pull
docker compose -f docker-compose.prod.yml --env-file .env up -d
```

4. Comprueba logs: `docker compose logs -f backend`.

---

## Paso 11 — Application Load Balancer

Si seguís el **ASG** del [Paso 9](#paso-9--lanzar-la-api-una-ec2-o-auto-scaling-group), creá **primero** el **Target Group** (pasos 4–5 abajo), luego el **ASG**, y después completá el **ALB** y el **listener** hacia ese Target Group (o creá TG + ALB y enlazá el ASG al TG cuando exista).

1. **EC2** → **Load Balancers** → **Create** → **Application Load Balancer**.
2. Esquema **internet-facing**, VPC y **subredes públicas** (dos AZ).
3. Security group: **sg-alb**.
4. **Target group:** tipo **Instance**, protocolo **HTTP**, puerto **80**, health check path **`/q/health`** (nginx reenvía `/q/` al backend).
5. Si usas **una EC2**, regístrala a mano en el target group. Si usas **ASG**, en el grupo elige **Attach to an existing load balancer** y este target group (o asocia el TG al ASG tras crearlo).
6. Crea el ALB y espera a que los targets pasen a **healthy**.

Prueba en el navegador: `http://DNS-DEL-ALB/q/health`.

---

## Paso 12 — Frontends (admin y menú)

En tu PC:

```bash
# Sustituye por la URL pública de tu API (ALB o dominio + HTTPS)
export VITE_API_URL=http://DNS-DEL-ALB

cd frontend/admin && npm ci && npm run build
cd ../menu && npm ci && npm run build
```

Sube cada `dist/` a su bucket S3 (y si usas website hosting o CloudFront, configura el origen).  
**CORS:** el bucket de imágenes y la API deben permitir el **origen** desde el que sirves el admin/menú (dominio CloudFront o S3 website).

---

## Paso 13 — Dominio y HTTPS (opcional pero recomendado)

1. **ACM** (Certificate Manager) en **us-east-1**: solicita certificado para `api.tudominio.com` y/o frontends (validación DNS).
2. En el **ALB**, añade listener **443** con ese certificado y reenvía al target group.
3. **Route 53:** registro ALIAS al ALB.

---

## Paso 14 — EC2 ETL / ML (opcional)

Arquitectura objetivo: **instancia dedicada** (no el ASG de la API), `sg-etl`, rol **ETL** (paso 6.2), **cron** + Python como en [ml-segmentation/README.md](./ml-segmentation/README.md) para entrenar y subir el artefacto al bucket de **§5.3**.

---

## Paso 15 — Checklist final

- [ ] `/q/health` responde OK detrás del ALB.
- [ ] Registro/login en admin funciona.
- [ ] Menú público carga y los eventos aparecen en DynamoDB (métricas o “Explore items”).
- [ ] Subida de imagen crea objeto en S3 y la URL se ve en el menú.
- [ ] Recomendaciones: con ítems en el carrito, el panel del menú muestra sugerencias (mismo backend).
- [ ] (Opcional) VPC endpoints S3 + DynamoDB en rutas privadas; worker ETL con cron.

---

## Si algo falla (ideas rápidas)

| Síntoma | Qué mirar |
|---------|-----------|
| Target **unhealthy** | **`sg-api`** permite 80 **desde** `sg-alb`; nginx y backend levantados; health en `/q/health`. |
| Backend no conecta a RDS | `sg-rds` permite 5432 desde **`sg-api`**; `DB_URL` y credenciales correctas; RDS en subred alcanzable desde la EC2. |
| Errores S3/Dynamo | Rol IAM adjunto a la instancia; nombres de bucket/tabla; región consistente. |
| CORS en el navegador | Orígenes permitidos en API (Quarkus ya tiene CORS amplio en dev; revisar prod) y en S3 si aplica. |

---

## Coste y siguiente lectura

Orden de magnitud de costes: [aws-deploy-guide.md §17](./aws-deploy-guide.md#17-coste-orientativo-us-east-1-orden-de-magnitud). El **NAT Gateway** suele ser una partida importante; no te sorprenda si el total supera los 90 USD/mes.

Índice general: [aws-setup.md](./aws-setup.md).
