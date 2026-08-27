#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || -z "$1" ]]; then
  echo "Uso: $0 <databricks-profile>" >&2
  exit 1
fi

profile="$1"
catalog="lakehouse_rotaperfume"
warehouse_id="2f89b2234655e504"

# No Databricks Free Edition, o catálogo é garantido via SQL devido às
# restrições relacionadas ao Default Storage na criação pela API do catálogo.
databricks experimental aitools tools query \
  --warehouse "$warehouse_id" \
  --profile "$profile" \
  "CREATE CATALOG IF NOT EXISTS ${catalog}"

