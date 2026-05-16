#!/usr/bin/env bash
# Empaqueta cada Lambda en un directorio con un solo .py fuente + dependencias pip (Linux x86_64).
# En macOS/Windows usad Docker, p. ej.:
#   docker run --rm -v "$(pwd)/ml-training:/opt/ml" -w /opt/ml public.ecr.aws/sam/build-python3.12 bash scripts/build_lambda_dists.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${ROOT}/lambda_dist"
rm -rf "${DIST}"
mkdir -p "${DIST}/orchestrator" "${DIST}/worker"

cp "${ROOT}/orchestrator_lambda.py" "${DIST}/orchestrator/"
cp "${ROOT}/worker_lambda.py" "${DIST}/worker/"

echo "Instalando psycopg2-binary en orquestador..."
pip install --disable-pip-version-check -q -t "${DIST}/orchestrator" 'psycopg2-binary>=2.9'

echo "Instalando dependencias ML en worker..."
pip install --disable-pip-version-check -q -t "${DIST}/worker" 'joblib>=1.3' 'numpy>=1.24' 'scikit-learn>=1.3'

echo "Listo: ${DIST}/orchestrator (orchestrator_lambda.handler)"
echo "       ${DIST}/worker (worker_lambda.handler)"
