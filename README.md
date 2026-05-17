# Cloud Computing - TP3 - Terraform
### Grupo 3 - 2026Q1 - ITBA

## Introducción

MenuQR es una aplicación multi-tenant para el manejo de menus digitales.  
Cada restaurante administra su carta desde un panel web y los clientes acceden al menú mediante un código QR desde su celular,
Además, se recompilan datos de interacción que se usan para analitica y entrenamiento de modelos de recomendaciones personalizados a cada restaurante

## Arquitectura

![Diagrama de arquitectura AWS](./Architecture.png)

## Requerimientos

Despliegue en **AWS** desde Linux, macOS o [WSL 2](https://learn.microsoft.com/es-es/windows/wsl/install) en Windows. Los scripts usan `bash`.

### Cuenta y credenciales AWS

| Requisito | Detalle                                                                                          |
|-----------|--------------------------------------------------------------------------------------------------|
| Cuenta AWS | Permisos para VPC, RDS, ECS, Lambda, S3, DynamoDB, ECR, etc.                                     |
| Rol **LabRole** | De **AWS Academy** (`data.aws_iam_role.lab_role` en Terraform)                                   |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2 | `aws configure` o `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y, si aplica, `AWS_SESSION_TOKEN` |

```bash
aws sts get-caller-identity
```

[Configurar el AWS CLI](https://docs.aws.amazon.com/es_es/cli/latest/userguide/cli-chap-configure.html).

### Herramientas de despliegue

| Herramienta | Versión | Uso en AWS |
|-------------|---------|------------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | ≥ **1.8.5** | Infraestructura (`terraform apply`) |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | v2 | Deploy, `aws s3 sync`, ECR |
| [Docker](https://docs.docker.com/engine/install/) | Reciente | Imagen del backend → ECR |
| [JDK](https://adoptium.net/) + [Maven](https://maven.apache.org/install.html) | Java **21**, Maven 3.9+ | Build Quarkus (`deploy-backend.sh`) |
| [Node.js](https://nodejs.org/) | **20 LTS** + npm | Build SPAs → S3 (`deploy-frontends.sh`) |
| [Python](https://www.python.org/downloads/) + **pip** | **3.12** | Empaquetado Lambdas ML (`build_lambda_dists.sh`; en macOS/Windows usar Docker con imagen SAM Python 3.12) |

Providers Terraform: **hashicorp/aws** (≥ 5.71.0), **hashicorp/archive** (≥ 2.0).

### Comandos por script

| Script | Herramientas en `PATH` |
|--------|------------------------|
| `terraform/scripts/deploy.sh` | `terraform`, `aws`, `bash` |
| `terraform/scripts/deploy-backend.sh` | `terraform`, `docker`, `mvn`, `aws` |
| `terraform/scripts/deploy-frontends.sh` | `terraform`, `npm`, `aws` |
| `ml-training/scripts/build_lambda_dists.sh` | `pip`, `bash` |

## Scripts (`terraform/scripts/`)

| Script | Uso                                                             |
|--------|-----------------------------------------------------------------|
| `deploy.sh` | **Completo:** Lambdas → `terraform apply` → backend → frontends |
| `deploy-backend.sh` | Buildea imagen y sube a ECS                                     |
| `deploy-frontends.sh` | Build Vite + sync S3                                            |

El empaquetado de Lambdas ocurre en `ml-training/scripts/build_lambda_dists.sh` (lo invoca `deploy.sh`).

## Instrucciones de Ejecución
### Paso a paso

```bash
bash ml-training/scripts/build_lambda_dists.sh
cd terraform && terraform init && terraform apply
bash terraform/scripts/deploy-backend.sh
bash terraform/scripts/deploy-frontends.sh
```

### Alternativa - Script completo

```bash
bash terraform/scripts/deploy.sh
```
### Outputs útiles

```bash
terraform output backend_api_url
terraform output frontend_admin_website_url
terraform output frontend_menu_website_url
```

### Justificación del uso de scripts Bash

La subida de imagenes a ECR y de archivos de los sitios web a los S3 se realiza mediante scripts. 
Si bien esto tecnicamente podria hacerse mediante terraform, no lo consideramos una buena practica, puesto que Terraform está 
orientado al aprovisionamiento y gestión declarativa de infraestructura, no al build ni despliegue de artefactos de aplicación.

Separar estas responsabilidades permite:

- Mantener los terraform apply idempotentes y más predecibles;
- Evitar que cambios frecuentes de código generen cambios innecesarios en la infraestructura;
- Desacoplar el ciclo de vida de la aplicación del de la infraestructura;

Por este motivo, Terraform se utiliza únicamente para crear y configurar la infraestructura necesaria, mientras que los scripts Bash se encargan de:

- Construir y subir imágenes Docker a ECR;
- Empaquetar y desplegar Lambdas;
- Compilar y sincronizar los frontends en los buckets S3 correspondientes;

## Instrucciones de Prueba

Tras ejecutar los scripts de deploy de backend y frontends, las URL de los mismos se veran en la terminal.
En primer lugar, se debe ingresar a la pagina de admin y crear un usuario.
Al crearlo, se pueden cargar platos del menu, ver ordenes, o cargar mesas. 
Al cargar una mesa se obtiene un QR dirigido a la pagina del Menu desde donde se pueden ver los platos disponibles e iniciar una orden

El entrenamiento de modelos es responsabilidad de las lambdas.
Se usa EventBridge para llamar a una Lambda orquestadora según un CRON ,el cual se define como variable en terraform, pero por defecto es de 1 vez por dia.
Alternativamente, se puede ejecutar manualmente la Lambda. Esta Lambda se encarga de obtener todos los tenants de la rds y enviar un request por tenant a un SQS para que le llegue a la otra Lambda,
la que se encarga de usar las metricas de ese tenant para entrenar un modelo de recomendaciones de platos. 
Los modelos se guardan en S3, y los usa el backend para dar recomendaciones de platos.

Cabe aclarar que, en caso de no tener cargado un modelo aún, el backend genera recomendaciones aleatorias. 
Asimismo, si un modelo se entrena apenas se levanta la aplicación, no habra datos suficientes para que el modelo pueda ser util. Aun así, el modelo será generado y almacenado en el bucket correspondiente.

Las recomendaciones se muestran en el modal que se ve antes de confirmar la orden.

Se puede invocar la Lambda orquestradora fuera del momento del cron para verificar la carga de modelos usando la consola de AWS


```bash
aws lambda invoke \
  --function-name menuqr-ml-orchestrator \
  --region us-east-1 \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/orchestrator-out.json

cat /tmp/orchestrator-out.json
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
| `toset` | `s3.tf`, `vpc_endpoint.tf` — `for_each` |
| `jsonencode` | `ecs.tf` — task definition (contenedor) |
| `coalesce` | `modules/python-lambda` — VPC SG |

### Meta-argumentos

| Meta-argumento | Ejemplo |
|----------------|---------|
| `for_each` | Buckets S3, gateway VPC endpoints |
| `depends_on` | ECS service → ALB listener; políticas S3 |
| `lifecycle` | Security groups (`create_before_destroy`); ECS `ignore_changes` en `desired_count` |
| `dynamic` | Bloque `vpc_config` en módulo Lambda |

