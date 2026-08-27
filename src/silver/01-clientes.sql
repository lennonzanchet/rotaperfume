CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes AS
WITH clientes_normalizados AS (
  SELECT
    try_cast(cliente_id AS BIGINT) AS cliente_id,
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj,
    initcap(lower(regexp_replace(trim(razao_social), '\\s+', ' '))) AS razao_social,
    segmento,
    cidade,
    uf,
    bairro,
    coalesce(
      try_to_date(trim(data_cadastro)),
      try_to_date(trim(data_cadastro), 'dd/MM/yyyy')
    ) AS data_cadastro,
    CASE upper(trim(ativo))
      WHEN 'S' THEN true
      WHEN 'N' THEN false
    END AS ativo
  FROM lakehouse_rotaperfume.bronze.clientes
),
clientes_ranqueados AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY cnpj
      ORDER BY data_cadastro ASC NULLS LAST, cliente_id ASC
    ) AS ordem_cadastro
  FROM clientes_normalizados
),
duplicidades AS (
  SELECT
    cnpj,
    collect_list(CASE WHEN ordem_cadastro > 1 THEN cliente_id END) AS cliente_ids_duplicados,
    count(*) AS _linhas_origem
  FROM clientes_ranqueados
  GROUP BY cnpj
)
SELECT
  principal.cliente_id,
  principal.cnpj,
  principal.razao_social,
  principal.segmento,
  principal.cidade,
  principal.uf,
  principal.bairro,
  principal.data_cadastro,
  principal.ativo,
  duplicidades.cliente_ids_duplicados,
  current_timestamp() AS _processado_em,
  duplicidades._linhas_origem
FROM clientes_ranqueados AS principal
INNER JOIN duplicidades
  ON principal.cnpj <=> duplicidades.cnpj
WHERE principal.ordem_cadastro = 1;

COMMENT ON TABLE lakehouse_rotaperfume.silver.clientes IS
  'Clientes limpos e deduplicados por CNPJ a partir da camada Bronze.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cnpj COMMENT
  'CNPJ normalizado como texto com exatamente 14 dígitos.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cliente_ids_duplicados COMMENT
  'IDs dos cadastros descartados ao manter o cadastro mais antigo de cada CNPJ.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN _linhas_origem COMMENT
  'Quantidade de registros Bronze que originaram o cliente Silver.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  DROP CONSTRAINT IF EXISTS clientes_cnpj_14;
ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_cnpj_14 CHECK (length(cnpj) = 14);
ALTER TABLE lakehouse_rotaperfume.silver.clientes
  DROP CONSTRAINT IF EXISTS clientes_data_cadastro_obrigatoria;
ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT clientes_data_cadastro_obrigatoria CHECK (data_cadastro IS NOT NULL);
