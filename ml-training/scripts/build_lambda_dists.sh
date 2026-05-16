#!/usr/bin/env bash
# Construye lambda_dist/worker y lambda_dist/orchestrator para empaquetado Terraform (Linux x86_64).
# En macOS/Windows usad Docker, p. ej.:
#   docker run --rm -v "$(pwd)/ml-training:/opt/ml" -w /opt/ml public.ecr.aws/sam/build-python3.12 bash scripts/build_lambda_dists.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${ROOT}/lambda_dist"
rm -rf "${DIST}"
mkdir -p "${DIST}/worker" "${DIST}/orchestrator"
cp "${ROOT}/recommendations_etl.py" "${DIST}/worker/"
cp "${ROOT}/worker_lambda.py" "${DIST}/worker/"
cp "${ROOT}/recommendations_etl.py" "${DIST}/orchestrator/"
cp "${ROOT}/orchestrator_lambda.py" "${DIST}/orchestrator/"
echo "Instalando dependencias ML en paquete worker..."
pip install --disable-pip-version-check -q -t "${DIST}/worker" 'joblib>=1.3' 'numpy>=1.24' 'scikit-learn>=1.3'
echo "Instalando psycopg2-binary en paquete orquestador..."
pip install --disable-pip-version-check -q -t "${DIST}/orchestrator" 'psycopg2-binary>=2.9'
echo "Listo: ${DIST}/worker y ${DIST}/orchestrator"
