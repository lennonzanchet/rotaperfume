#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || -z "$1" ]]; then
  echo "Uso: $0 <databricks-profile>" >&2
  exit 1
fi

profile="$1"
catalog="lakehouse_rotaperfume"
erp_dir="dados/erp"
crm_dir="dados/crm"
erp_dest="dbfs:/Volumes/${catalog}/bronze/raw/erp/"
crm_dest="dbfs:/Volumes/${catalog}/bronze/raw/crm/"

if [[ ! -d "$erp_dir" ]]; then
  echo "Erro: diretório obrigatório não encontrado: $erp_dir" >&2
  exit 1
fi

if [[ ! -d "$crm_dir" ]]; then
  echo "Erro: diretório obrigatório não encontrado: $crm_dir" >&2
  exit 1
fi

shopt -s nullglob
erp_files=("$erp_dir"/*.csv)
crm_files=("$crm_dir"/*.csv)

if [[ ${#erp_files[@]} -eq 0 ]]; then
  echo "Erro: nenhum arquivo CSV encontrado em $erp_dir" >&2
  exit 1
fi

if [[ ${#crm_files[@]} -eq 0 ]]; then
  echo "Erro: nenhum arquivo CSV encontrado em $crm_dir" >&2
  exit 1
fi

echo "Iniciando upload dos arquivos Raw para o Unity Catalog Volume..."

echo "Enviando arquivos ERP para $erp_dest"
for file in "${erp_files[@]}"; do
  databricks fs cp "$file" "${erp_dest}$(basename "$file")" --overwrite --profile "$profile"
done

echo "Enviando arquivos CRM para $crm_dest"
for file in "${crm_files[@]}"; do
  databricks fs cp "$file" "${crm_dest}$(basename "$file")" --overwrite --profile "$profile"
done

echo "Upload dos arquivos Raw concluído com sucesso."

