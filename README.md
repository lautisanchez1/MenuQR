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
├── infrastructure/            # AWS docs (ASG, VPC endpoints, S3 modelos, ETL EC2)
├── docker-compose.yml         # Local development
└── docker-compose.prod.yml    # Production deployment
```

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Java 21 (for local backend development)
- Node.js 20 (for local frontend development)
- Terraform >= 1.6 + AWS credentials (Academy Learner Lab works)

### 1. Provision Cognito (required before first `docker compose up`)

The backend authenticates against a real Cognito user pool — it will refuse
to start without one. There are no offline / no-auth defaults; this matches
AWS standard practice (no app should run un-authenticated, even locally).

```bash
cd infrastructure/terraform
terraform init
terraform apply -target=module.cognito
```

The Cognito module is self-contained — it doesn't create RDS, EC2, or VPC.
Apply takes ~30s and costs nothing in the AWS free tier.

Grab the outputs you'll need next:

```bash
terraform output cognito_issuer_url
terraform output cognito_user_pool_client_id
terraform output cognito_hosted_ui_base_url
```

**On AWS Academy / Learner Lab:** when the lab session resets, the user pool
is destroyed. Re-run `terraform apply -target=module.cognito` and update
`.env` with the new outputs.

### 2. Environment Setup

```bash
cp .env.example .env
```

Open `.env` and paste the three terraform outputs from step 1 into:
- `COGNITO_ISSUER_URL`
- `COGNITO_CLIENT_ID`
- `VITE_COGNITO_HOSTED_UI_BASE_URL`

The other defaults (Postgres, MinIO, DynamoDB Local) work out of the box.

### 3. Start with Docker Compose

```bash
docker compose up
```

If the backend fails at boot with `Failed to load config value ... mp.jwt.verify.issuer`,
you skipped step 1 or 2 — the Cognito env vars are unset.

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

## License

MIT
