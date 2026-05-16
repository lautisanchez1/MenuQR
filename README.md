# MenuDigital (TP Cloud Computing, VibeCode~~~~)

A multi-tenant digital menu SaaS platform for restaurants. Customers scan a QR code to view menus on their phones, while restaurant owners get rich, real-time analytics.

## Features

- **Multi-tenant architecture**: Each restaurant has isolated data and their own login
- **Digital menu**: Mobile-first QR code menu viewer with dietary filters
- **Rich analytics**: View counts, item popularity, hourly heatmaps, session depth
- **Real-time dashboard**: Live activity tracking with 30-second refresh
- **Menu management**: Full CRUD for sections and items with image upload

## Tech Stack

### Backend
- Quarkus 3 (Java 21)
- RESTEasy Reactive
- Hibernate ORM with Panache
- PostgreSQL 15
- DynamoDB (analytics events)
- S3 (image storage)
- SmallRye JWT

### Frontend
- React 18 + TypeScript
- Vite
- TailwindCSS + shadcn/ui
- React Query v5
- Recharts (analytics)

## Project Structure

```
menudigital/
├── backend/                    # Quarkus backend
│   ├── src/main/java/com/menudigital/
│   │   ├── domain/            # Pure Java domain models
│   │   ├── application/       # Use cases and DTOs
│   │   ├── infrastructure/    # DB, DynamoDB, S3 implementations
│   │   └── interfaces/rest/   # REST controllers
│   └── src/main/resources/
│       └── db/migration/      # Flyway migrations
├── frontend/
│   ├── admin/                 # Admin panel SPA
│   └── menu/                  # Public menu viewer SPA
├── infrastructure/
│   └── terraform/             # IaC con Terraform (TP3)
├── docker-compose.yml         # Local development
└── docker-compose.prod.yml    # Production deployment
```

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Java 21 (for local backend development)
- Node.js 20 (for local frontend development)

### 1. Environment Setup

```bash
# Copy the environment template
cp .env.example .env

# Edit .env with your settings (optional - defaults work for local development)
```

### 2. JWT Keys (Optional)

Development JWT keys are included in the repository. For production, generate new keys:

```bash
cd backend/src/main/resources
openssl genrsa -out privateKey.pem 2048
openssl rsa -pubout -in privateKey.pem -out publicKey.pem
```

### 3. Start with Docker Compose

```bash
docker-compose up
```

This starts:
- PostgreSQL on port 5432
- DynamoDB Local on port 8000
- Backend on port 8080
- Admin frontend on port 5174
- Menu frontend on port 5173

### 4. Access the Application

- **Admin Panel**: http://localhost:5174
- **Public Menu**: http://localhost:5173/menu/{slug}
- **API**: http://localhost:8080/api
- **Health Check**: http://localhost:8080/q/health

## API Endpoints

### Public (no auth)
- `GET /api/menu/{slug}` - Get public menu
- `POST /api/menu/{slug}/events` - Record analytics event
- `POST /api/menu/{slug}/recommendations` - Cart suggestions (same Quarkus backend; optional `menu_item_ids` in body)

### Auth
- `POST /api/auth/register` - Register restaurant
- `POST /api/auth/login` - Login

### Admin (JWT required)
- `GET /api/admin/menu` - Get full menu
- `POST/PUT/DELETE /api/admin/menu/sections/{id}` - Manage sections
- `POST/PUT/DELETE /api/admin/menu/items/{id}` - Manage items
- `PATCH /api/admin/menu/items/{id}/availability` - Toggle availability
- `POST /api/admin/upload` - Upload image
- `GET /api/admin/analytics` - Get analytics dashboard
- `GET /api/admin/analytics/realtime` - Get realtime stats

## Local Development

### Backend only
```bash
cd backend
./mvnw quarkus:dev
```

### Frontend only
```bash
cd frontend/admin
npm install && npm run dev

cd frontend/menu
npm install && npm run dev
```

## Production Deployment

See `infrastructure/aws-deploy-novatos.md` for a beginner step-by-step AWS deploy, or `infrastructure/aws-deploy-guide.md` for technical reference (index: `infrastructure/aws-setup.md`).

### Build backend
```bash
cd backend
./mvnw package
docker build -f src/main/docker/Dockerfile.jvm -t menudigital-backend .
```

### Build frontends
```bash
cd frontend/admin
npm run build

cd frontend/menu
npm run build
```

## Environment Variables

### Backend
| Variable | Description | Default |
|----------|-------------|---------|
| DB_URL | PostgreSQL connection URL | jdbc:postgresql://localhost:5432/menudigital |
| DB_USER | Database username | menudigital |
| DB_PASS | Database password | menudigital |
| AWS_REGION | AWS region | us-east-1 |
| S3_BUCKET | S3 bucket for images | menudigital-images |
| DYNAMO_TABLE | DynamoDB table name | menudigital-events |

### Frontend
| Variable | Description | Default |
|----------|-------------|---------|
| VITE_API_URL | Backend API URL | http://localhost:8080 |

---

## Infraestructura con Terraform (TP3)

### Estructura del proyecto Terraform

```
infrastructure/terraform/
├── main.tf                          # Recursos principales
├── variables.tf                     # Variables de entrada
├── outputs.tf                       # Valores de salida
├── terraform.tfvars                 # Valores de las variables
├── datasources.tf                   # Data sources (AZs, región)
├── provider.tf                      # Configuración del provider AWS
├── version.tf                       # Versión requerida de Terraform
└── modules/
    ├── menu_network/                # Módulo propio: VPC y networking
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── s3-spa-bucket/               # Módulo propio: S3 público para SPAs
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── s3-private-versioned-bucket/ # Módulo propio: S3 privado con versionado
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Módulos

#### Módulos propios

**menu_network** — Crea la VPC completa con 4 tiers de subnets (públicas, backend, base de datos y ML) distribuidas en 2 AZs, junto con el NAT Gateway, Internet Gateway y las route tables correspondientes. Usa internamente el módulo externo `terraform-aws-modules/vpc/aws`.

**s3-spa-bucket** — Crea un bucket S3 configurado para hosting de sitios web estáticos (SPAs). Incluye la política de acceso público para lectura, configuración de index.html como documento principal y de error. Se usa para el frontend de admin y el de usuarios.

**s3-private-versioned-bucket** — Crea un bucket S3 privado con versionado habilitado, encriptación AES256 y bloqueo total de acceso público. Se usa para almacenar modelos de ML e imágenes de usuarios.

#### Módulos externos

| Módulo | Versión | Uso |
|--------|---------|-----|
| `terraform-aws-modules/vpc/aws` | 5.5.1 | VPC, subnets, NAT Gateway, IGW |
| `terraform-aws-modules/rds/aws` | 6.10.0 | RDS PostgreSQL con multi-AZ |
| `terraform-aws-modules/security-group/aws` | 5.3.1 | Security groups para ALB, EC2, RDS y ML |
| `terraform-aws-modules/s3-bucket/aws` | 3.15.1 | Base para los módulos propios de S3 |

### Funciones de Terraform utilizadas

| Función | Dónde se usa | Para qué |
|---------|-------------|----------|
| `regex()` | `locals` | Extrae la versión major de PostgreSQL para el parameter group |
| `cidrsubnet()` | `menu_network` | Calcula los CIDRs de cada subnet a partir del CIDR de la VPC |
| `slice()` | `menu_network` | Toma las primeras 2 AZs disponibles de la región |
| `range()` | `menu_network` | Genera índices para iterar sobre las subnets |
| `concat()` | `locals` | Une las route tables de backend y ML para los VPC endpoints |
| `merge()` | Todos los recursos | Combina common_tags con tags específicos de cada recurso |
| `can()` | `locals` | Detecta si la instancia EC2 es Graviton para elegir la AMI correcta |
| `length()` | `aws_route` | Verifica si existen subnets de ML para crear la ruta NAT condicionalmente |

### Meta-argumentos utilizados

**count** — En `aws_route.ml_internet_via_nat` para crear la ruta al NAT Gateway solo si existen subnets de ML. La expresión `count = length(module.network.subnet_ids_ml) > 0 ? 1 : 0` crea el recurso condicionalmente.

**lifecycle** — En `aws_launch_template.app` con `create_before_destroy = true`. Esto asegura que al actualizar el launch template, Terraform cree el nuevo antes de destruir el anterior, para que el ASG nunca quede sin un template válido.

**depends_on** — En `aws_autoscaling_group.app` con `depends_on = [aws_lb_listener.http]`. Asegura que el ALB listener esté completamente creado antes de que el ASG empiece a registrar instancias en el target group.

**for_each** — En `module.s3_private_buckets` para crear los buckets privados (ml-models y user-images) con un solo bloque de código, iterando sobre un mapa de nombres en vez de duplicar el módulo.

### Recursos creados

| Recurso | Descripción |
|---------|-------------|
| VPC | Red privada 172.30.0.0/16 con 7 subnets en 2 AZs |
| ALB | Application Load Balancer público en subnets públicas |
| Target Group | Health check en /health, puerto 80 |
| ASG | Auto Scaling Group (min: 1, desired: 2, max: 4) con Launch Template |
| Launch Template | AMI Amazon Linux 2023, t3.micro, disco gp3 30GB encriptado |
| RDS | PostgreSQL 16, db.t4g.micro, multi-AZ, contraseña en Secrets Manager |
| DynamoDB | Tabla menuqr-events con PK/SK y LSI por eventType, pay-per-request |
| S3 (SPAs) | 2 buckets públicos con website hosting (admin y users) |
| S3 (privados) | 2 buckets privados con versionado y encriptación (ML models y user images) |
| VPC Endpoints | Gateway endpoints para S3 y DynamoDB (sin pasar por NAT) |
| Security Groups | 4 SGs: ALB (HTTP público), EC2 app (HTTP desde ALB), RDS (PostgreSQL desde EC2), ML (solo egress) |
| NAT Gateway | Salida a internet para instancias en subnets privadas |
| Internet Gateway | Entrada desde internet hacia subnets públicas |

### Guía de ejecución paso a paso

#### Prerrequisitos

- Terraform v1.0 o superior
- AWS CLI instalado y configurado
- Credenciales de AWS (Access Key, Secret Key y Session Token del Learner Lab)

#### 1. Configurar credenciales de AWS

```bash
aws configure
# AWS Access Key ID: <tu access key>
# AWS Secret Access Key: <tu secret key>
# AWS Session Token: <dejar vacío, se configura aparte>
# Default region name: us-east-1
# Default output format: json

aws configure set aws_session_token <tu session token>
```

Verificar que funcione:

```bash
aws sts get-caller-identity
```

#### 2. Inicializar Terraform

```bash
cd infrastructure/terraform
terraform init
```

Descarga los providers y módulos externos. No toca AWS.

#### 3. Validar la configuración

```bash
terraform validate
```

Verifica que no haya errores de sintaxis. No toca AWS.

#### 4. Ver el plan de ejecución

```bash
terraform plan
```

Muestra qué recursos se van a crear, modificar o destruir. No toca AWS.

#### 5. Aplicar la infraestructura

```bash
terraform apply
```

Escribir `yes` cuando pida confirmación. La creación tarda aproximadamente 15-20 minutos (el RDS es lo más lento).

#### 6. Destruir la infraestructura

```bash
terraform destroy
```

Escribir `yes` cuando pida confirmación. Elimina todos los recursos creados de AWS.

#### Nota sobre credenciales del Learner Lab

Las credenciales del Learner Lab cambian cada vez que se inicia el lab. Si se vence la sesión, hay que volver a configurar `aws configure` con las nuevas credenciales antes de correr cualquier comando de Terraform.

## License

MIT
