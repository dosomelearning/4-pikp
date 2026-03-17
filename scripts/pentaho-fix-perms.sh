#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PENTAHO_WORKSPACE="${ROOT_DIR}/infra/platform/pentaho"

if [[ ! -d "${PENTAHO_WORKSPACE}" ]]; then
  echo "ERROR: Pentaho workspace not found: ${PENTAHO_WORKSPACE}"
  exit 1
fi

# WebSpoon container runs as uid/gid 999 (tomcat). Host files are owned by raven.
# Make workspace writable from both sides to avoid save failures in GUI.
chmod -R a+rwX "${PENTAHO_WORKSPACE}"

echo "Pentaho workspace permissions normalized: ${PENTAHO_WORKSPACE}"

