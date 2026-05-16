# Cloud Computing - TP3 - Terraform
### Grupo 3 - 2026Q1 - ITBA

## Introducción

MenuQR es una aplicación multi-tenant para el manejo de menus digitales.  
Cada restaurante administra su carta desde un panel web y los clientes acceden al menú mediante un código QR desde su celular,
Además, se recompilan datos de interacción que se usan para analitica y entrenamiento de modelos de recomendaciones personalizados a cada restaurante

## Arquitectura

## Requerimientos


- Terraform ≥ 1.8.5, AWS CLI, Docker, Maven, Node.js
- Cuenta AWS con rol **LabRole**
- Credenciales: `aws sts get-caller-identity`

Aclaración: Los scripts fueron probados en Linux, aunque deberian funcionar tambien en MAC o en Windows mediante el uso de WSL

## Instrucciones de Ejecución

### 1. Preparar los zip con el codigo de las lambda

```bash
bash ml-training/scripts/build_lambda_dists.sh
```

### 2. Aplicar los archivos .tf

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Deployar el backend y subir los frontend estaticos

```bash
bash scripts/deploy-backend.sh
bash scripts/deploy-frontends.sh
```

### Alternativa -> Script con el proceso completo

```bash
bash scripts/deploy.sh`
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

