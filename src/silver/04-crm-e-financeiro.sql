CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores AS
SELECT
  try_cast(vendedor_id AS BIGINT) AS vendedor_id,
  nome,
  regiao,
  uf,
  coalesce(
    try_to_date(trim(data_admissao)),
    try_to_date(trim(data_admissao), 'dd/MM/yyyy')
  ) AS data_admissao,
  coalesce(
    try_to_date(trim(data_desligamento)),
    try_to_date(trim(data_desligamento), 'dd/MM/yyyy')
  ) AS data_desligamento,
  try_cast(meta_mensal AS DECIMAL(18, 2)) AS meta_mensal,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.silver.vendedores IS
  'Vendedores tipados, mantendo datas de admissão e desligamento para análise histórica.';
ALTER TABLE lakehouse_rotaperfume.silver.vendedores ALTER COLUMN data_desligamento COMMENT
  'Data de desligamento preservada; nula enquanto o vendedor não estiver desligado.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira AS
WITH carteira_tipada AS (
  SELECT
    try_cast(carteira_id AS BIGINT) AS carteira_id,
    try_cast(cliente_id AS BIGINT) AS cliente_id,
    try_cast(vendedor_id AS BIGINT) AS vendedor_id,
    coalesce(
      try_to_date(trim(data_inicio)),
      try_to_date(trim(data_inicio), 'dd/MM/yyyy')
    ) AS data_inicio,
    coalesce(
      try_to_date(trim(data_fim)),
      try_to_date(trim(data_fim), 'dd/MM/yyyy')
    ) AS data_fim
  FROM lakehouse_rotaperfume.bronze.carteira
)
SELECT
  carteira.carteira_id,
  carteira.cliente_id,
  carteira.vendedor_id,
  carteira.data_inicio,
  carteira.data_fim,
  coalesce(
    carteira.data_inicio <= current_date()
      AND (carteira.data_fim IS NULL OR carteira.data_fim >= current_date())
      AND (vendedores.data_desligamento IS NULL OR vendedores.data_desligamento > current_date()),
    false
  ) AS vigente,
  coalesce(
    vendedores.data_desligamento IS NOT NULL
      AND carteira.data_inicio <= vendedores.data_desligamento
      AND (carteira.data_fim IS NULL OR carteira.data_fim > vendedores.data_desligamento),
    false
  ) AS orfao_vendedor_desligado,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM carteira_tipada AS carteira
LEFT JOIN lakehouse_rotaperfume.silver.vendedores AS vendedores
  ON carteira.vendedor_id = vendedores.vendedor_id;

COMMENT ON TABLE lakehouse_rotaperfume.silver.carteira IS
  'Histórico de carteiras com vigência calculada e anomalias de vendedor desligado sinalizadas.';
ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN vigente COMMENT
  'Indica vínculo vigente considerando datas da carteira e desligamento do vendedor.';
ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN orfao_vendedor_desligado COMMENT
  'Sinaliza carteira que permaneceu vinculada após o desligamento do vendedor.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades AS
SELECT
  try_cast(oportunidade_id AS BIGINT) AS oportunidade_id,
  try_cast(cliente_id AS BIGINT) AS cliente_id,
  try_cast(vendedor_id AS BIGINT) AS vendedor_id,
  origem,
  coalesce(
    try_to_date(trim(data_abertura)),
    try_to_date(trim(data_abertura), 'dd/MM/yyyy')
  ) AS data_abertura,
  etapa,
  etapa = 'Fechado ganho' AS fechado_ganho,
  etapa = 'Fechado perdido' AS fechado_perdido,
  try_cast(probabilidade_pct AS DECIMAL(9, 4)) AS probabilidade_pct,
  try_cast(valor_estimado AS DECIMAL(18, 2)) AS valor_estimado,
  coalesce(
    try_to_date(trim(data_fechamento)),
    try_to_date(trim(data_fechamento), 'dd/MM/yyyy')
  ) AS data_fechamento,
  try_cast(ciclo_dias AS INT) AS ciclo_dias,
  motivo_perda,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.oportunidades;

COMMENT ON TABLE lakehouse_rotaperfume.silver.oportunidades IS
  'Oportunidades comerciais tipadas, preservando as etapas reais originadas pelo CRM.';
ALTER TABLE lakehouse_rotaperfume.silver.oportunidades ALTER COLUMN fechado_ganho COMMENT
  'Indica exatamente a etapa Fechado ganho informada pelo CRM.';
ALTER TABLE lakehouse_rotaperfume.silver.oportunidades ALTER COLUMN fechado_perdido COMMENT
  'Indica exatamente a etapa Fechado perdido informada pelo CRM.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas AS
SELECT
  try_cast(visita_id AS BIGINT) AS visita_id,
  try_cast(cliente_id AS BIGINT) AS cliente_id,
  try_cast(vendedor_id AS BIGINT) AS vendedor_id,
  coalesce(
    try_to_date(trim(data_visita)),
    try_to_date(trim(data_visita), 'dd/MM/yyyy')
  ) AS data_visita,
  resultado,
  try_cast(duracao_min AS INT) AS duracao_min,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.visitas;

COMMENT ON TABLE lakehouse_rotaperfume.silver.visitas IS
  'Visitas comerciais tipadas sem descarte de registros da camada Bronze.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos AS
SELECT
  try_cast(pagamento_id AS BIGINT) AS pagamento_id,
  try_cast(pedido_id AS BIGINT) AS pedido_id,
  forma_pagamento,
  try_cast(parcelas AS INT) AS parcelas,
  try_cast(valor AS DECIMAL(18, 2)) AS valor,
  try_cast(taxa_pct AS DECIMAL(9, 4)) AS taxa_pct,
  try_cast(valor_liquido AS DECIMAL(18, 2)) AS valor_liquido,
  coalesce(
    try_to_date(trim(data_vencimento)),
    try_to_date(trim(data_vencimento), 'dd/MM/yyyy')
  ) AS data_vencimento,
  coalesce(
    try_to_date(trim(data_pagamento)),
    try_to_date(trim(data_pagamento), 'dd/MM/yyyy')
  ) AS data_pagamento,
  status_pagamento,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pagamentos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pagamentos IS
  'Pagamentos tipados com valores monetários e datas de vencimento e pagamento.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque AS
WITH estoque_tipado AS (
  SELECT
    coalesce(
      try_to_date(trim(data_snapshot)),
      try_to_date(trim(data_snapshot), 'dd/MM/yyyy')
    ) AS data_snapshot,
    sku,
    try_cast(saldo AS BIGINT) AS saldo
  FROM lakehouse_rotaperfume.bronze.estoque
)
SELECT
  data_snapshot,
  sku,
  saldo,
  saldo = 0 AS ruptura,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM estoque_tipado;

COMMENT ON TABLE lakehouse_rotaperfume.silver.estoque IS
  'Posições de estoque tipadas com indicador de ruptura derivado do saldo.';
ALTER TABLE lakehouse_rotaperfume.silver.estoque ALTER COLUMN ruptura COMMENT
  'Indica ruptura quando o saldo numérico é igual a zero.';

