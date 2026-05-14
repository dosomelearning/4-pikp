#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPERSET_HOME_DIR="${ROOT_DIR}/data/superset"
SUPERSET_CONFIG_DIR="${ROOT_DIR}/infra/platform/superset"

mkdir -p "${SUPERSET_HOME_DIR}"
mkdir -p "${SUPERSET_CONFIG_DIR}"

chmod -R a+rwX "${SUPERSET_HOME_DIR}"
chmod -R a+rX "${SUPERSET_CONFIG_DIR}"

echo "Superset paths prepared:"
echo "- ${SUPERSET_HOME_DIR}"
echo "- ${SUPERSET_CONFIG_DIR}"
