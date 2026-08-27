CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos AS
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  try_cast(preco_tabela AS DECIMAL(18, 2)) AS preco_tabela,
  try_cast(custo_unitario AS DECIMAL(18, 2)) AS custo_unitario,
  unidade,
  CASE upper(trim(ativo))
    WHEN 'S' THEN true
    WHEN 'N' THEN false
  END AS ativo,
  coalesce(
    try_to_date(trim(data_lancamento)),
    try_to_date(trim(data_lancamento), 'dd/MM/yyyy')
  ) AS data_lancamento,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.silver.produtos IS
  'Produtos tipados a partir da camada Bronze, preservando seus atributos comerciais.';
ALTER TABLE lakehouse_rotaperfume.silver.produtos ALTER COLUMN ativo COMMENT
  'Indica se o SKU permanece ativo no cadastro de produtos.';
ALTER TABLE lakehouse_rotaperfume.silver.produtos ALTER COLUMN data_lancamento COMMENT
  'Data de lançamento convertida de forma tolerante a formatos mistos.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido AS
WITH itens_tipados AS (
  SELECT
    try_cast(item_id AS BIGINT) AS item_id,
    try_cast(pedido_id AS BIGINT) AS pedido_id,
    sku,
    try_cast(quantidade AS INT) AS quantidade,
    try_cast(preco_praticado AS DECIMAL(18, 2)) AS preco_praticado,
    try_cast(desconto_pct AS DECIMAL(9, 4)) AS desconto_pct,
    try_cast(valor_bruto AS DECIMAL(18, 2)) AS valor_bruto
  FROM lakehouse_rotaperfume.bronze.itens_pedido
)
SELECT
  itens.item_id,
  itens.pedido_id,
  itens.sku,
  itens.quantidade,
  itens.quantidade < 0 AS devolucao,
  abs(itens.quantidade) AS quantidade_abs,
  itens.preco_praticado,
  itens.desconto_pct,
  itens.valor_bruto,
  coalesce(NOT produtos.ativo, false) AS sku_descontinuado,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM itens_tipados AS itens
LEFT JOIN lakehouse_rotaperfume.silver.produtos AS produtos
  ON itens.sku = produtos.sku;

COMMENT ON TABLE lakehouse_rotaperfume.silver.itens_pedido IS
  'Itens de pedido tipados, incluindo devoluções e a situação atual do SKU.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN devolucao COMMENT
  'Indica quantidade negativa, que representa uma devolução legítima.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN quantidade_abs COMMENT
  'Quantidade em valor absoluto, preservando a quantidade original com sinal.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN sku_descontinuado COMMENT
  'Indica item associado a um produto que não está mais ativo.';

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido
  DROP CONSTRAINT IF EXISTS itens_pedido_quantidade_abs_positiva;
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido
  ADD CONSTRAINT itens_pedido_quantidade_abs_positiva CHECK (quantidade_abs > 0);

