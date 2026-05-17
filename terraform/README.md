# Cloud Computing - TP3 - Terraform
### Grupo 3 - 2026Q1 - ITBA

## Introducción

MenuQR es una aplicación multi-tenant para el manejo de menus digitales.  
Cada restaurante administra su carta desde un panel web y los clientes acceden al menú mediante un código QR desde su celular,
Además, se recompilan datos de interacción que se usan para analitica y entrenamiento de modelos de recomendaciones personalizados a cada restaurante

## Arquitectura

## CI (GitHub Actions)

Workflow [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml):

| Job | Cuándo | Qué hace |
|-----|--------|----------|
| **Init & validate** | Siempre en PR/push | `build_lambda_dists.sh` → `terraform fmt -check` → `init -backend=false` → `validate` |
| **Plan (AWS)** | Si hay secrets AWS en el repo | `plan -var-file=terraform.tfvars` y sube artefacto `plan.txt` |

Secrets en GitHub (**Settings → Secrets → Actions**), típico con credenciales temporales de AWS Academy:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (requerido con LabRole / STS)

Sin secrets, el job **Plan** termina en verde con un mensaje informativo; **Init & validate** siempre corre.

## Requerimientos


- Terraform ≥ 1.8.5, AWS CLI, Docker, Maven, Node.js
- Cuenta AWS con rol **LabRole**
- Credenciales: `aws sts get-caller-identity`

Aclaración: Los scripts fueron probados en Linux, aunque deberian funcionar tambien en MAC o en Windows mediante el uso de WSL

## Scripts (`terraform/scripts/`)

| Script | Uso |
|--------|-----|
| `deploy.sh` | **Completo:** Lambdas → `terraform apply` → backend → frontends |
| `deploy-backend.sh` | Solo ECR + ECS (infra ya aplicada) |
| `deploy-frontends.sh` | Solo build Vite + sync S3 |
| `terraform-init-remote.sh` | Bootstrap state remoto S3 + `terraform init` |

El empaquetado de Lambdas sigue en `ml-training/scripts/build_lambda_dists.sh` (lo invoca `deploy.sh`).

## Instrucciones de Ejecución

### Todo en uno (recomendado)

```bash
bash terraform/scripts/deploy.sh
```

Variables útiles: `SKIP_TERRAFORM_APPLY=1` (solo app), `TERRAFORM_PLAN_ONLY=1` (solo plan), `IMAGE_TAG`, `SKIP_MVN`, `SKIP_INSTALL`.

### Paso a paso

```bash
bash ml-training/scripts/build_lambda_dists.sh
cd terraform && terraform init && terraform apply
bash terraform/scripts/deploy-backend.sh
bash terraform/scripts/deploy-frontends.sh
```

### Outputs útiles

```bash
terraform output backend_api_url
terraform output frontend_admin_website_url
terraform output frontend_menu_website_url
```

## Terraform

### Módulos propios

| Módulo | Uso                                          |
|--------|----------------------------------------------|
| `modules/python-lambda` | Lambda desde directorio (zip con `archive_file`) |
| `modules/s3-private` | Buckets privados versionados                 |
| `modules/s3-public-website` | SPAs con website hosting                     |

### Módulos externos

| Módulo | Uso |
|--------|-----|
| `terraform-aws-modules/vpc` | VPC, subredes, NAT |
| `terraform-aws-modules/rds-proxy` | RDS Proxy |

### Funciones

| Función | Ejemplo en el repo |
|---------|-------------------|
| `slice` | `locals.tf` — subredes / AZs |
| `cidrsubnets` | `locals.tf` — CIDRs por capa |
| `lower` / `replace` | `locals.tf` — `name_prefix` |
| `toset` | `s3.tf`, `vpc_endpoint.tf` — `for_each` |
| `jsonencode` | `ecs.tf` — task definition |
| `coalesce` | `modules/python-lambda` — VPC SG |

### Meta-argumentos

| Meta-argumento | Ejemplo |
|----------------|---------|
| `for_each` | Buckets S3, gateway VPC endpoints |
| `depends_on` | ECS service → ALB listener; políticas S3 |
| `lifecycle` | Security groups (`create_before_destroy`); ECS `ignore_changes` en `desired_count` |
| `dynamic` | Bloque `vpc_config` en módulo Lambda |

