#!/usr/bin/env bash
# Despliegue completo: Lambdas ML (dist), backend (ECR+ECS), frontends (S3).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/3 Lambda artifacts (ml-training)"
bash "${ROOT}/ml-training/scripts/build_lambda_dists.sh"

echo ""
echo "==> 2/3 Backend (ECR + ECS)"
bash "${ROOT}/scripts/deploy-backend.sh"

echo ""
echo "==> 3/3 Frontends (S3)"
bash "${ROOT}/scripts/deploy-frontends.sh"
