#!/bin/bash

# Log: sudo tail -f /var/log/menuqr-user-data.log

exec > >(tee /var/log/menuqr-user-data.log) 2>&1
set -euxo pipefail

yum update -y
yum install -y docker git openssl
systemctl enable --now docker

if ! yum install -y docker-compose-plugin; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  DC_VER="2.29.2"
  DC_ARCH=$(uname -m)
  curl -fsSL "https://github.com/docker/compose/releases/download/v${DC_VER}/docker-compose-linux-${DC_ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

APP_PARENT="/opt/menuqr"
APP_DIR="${APP_PARENT}/MenuQR"
mkdir -p "${APP_PARENT}"
cd "${APP_PARENT}"

if [ ! -d "${APP_DIR}/.git" ]; then
  git clone --depth 1 --branch main https://github.com/urielsv/MenuQR.git MenuQR
fi
cd "${APP_DIR}"

cat > .env <<'ENVEOF'
DB_URL=jdbc:postgresql://menuqr-db.c9auakcmctma.us-east-1.rds.amazonaws.com:5432/menuqr
DB_USER=postgres
DB_PASS=postgres
AWS_REGION=us-east-1
S3_BUCKET=menu-qr-images-bucket
S3_PUBLIC_URL=
DYNAMO_TABLE=menuqr-events
S3_ENDPOINT=
DYNAMO_ENDPOINT=
QUARKUS_PROFILE=prod
RECOMMENDATIONS_MODEL_S3_BUCKET=menu-qr-ml-models
RECOMMENDATIONS_MODEL_S3_KEY=recommendations/v1/model.joblib
ENVEOF
chmod 600 .env

if [ ! -f privateKey.pem ]; then
  openssl genrsa -out privateKey.pem 2048
  openssl rsa -in privateKey.pem -pubout -out publicKey.pem
  chmod 600 privateKey.pem
fi
mkdir -p ssl

docker compose -f infrastructure/docker/docker-compose.prod.yml up -d --build

echo "menuqr cleanscript finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
