CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos AS
WITH pedidos_tipados AS (
  SELECT
    try_cast(pedido_id AS BIGINT) AS pedido_id,
    try_cast(cliente_id AS BIGINT) AS cliente_id,
    try_cast(vendedor_id AS BIGINT) AS vendedor_id,
    coalesce(
      try_to_date(trim(data_pedido)),
      try_to_date(trim(data_pedido), 'dd/MM/yyyy')
    ) AS data_pedido,
    canal,
    status,
    try_cast(valor_total AS DECIMAL(18, 2)) AS valor_total,
    coalesce(status = 'Cancelado', false) AS cancelado
  FROM lakehouse_rotaperfume.bronze.pedidos
)
SELECT
  pedido_id,
  cliente_id,
  vendedor_id,
  data_pedido,
  canal,
  status,
  valor_total,
  cancelado,
  CASE
    WHEN cancelado THEN CAST(0 AS DECIMAL(18, 2))
    ELSE valor_total
  END AS valor_liquido,
  year(data_pedido) AS ano,
  month(data_pedido) AS mes,
  current_timestamp() AS _processado_em,
  CAST(1 AS BIGINT) AS _linhas_origem
FROM pedidos_tipados;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pedidos IS
  'Pedidos tipados e enriquecidos com indicadores de cancelamento e valor líquido.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN data_pedido COMMENT
  'Data do pedido convertida de ISO ou dd/MM/yyyy sem falha por formato inválido.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN cancelado COMMENT
  'Indica que o status de negócio do pedido é Cancelado.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN valor_liquido COMMENT
  'Valor total preservado para pedidos válidos e zerado para cancelamentos.';

ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  DROP CONSTRAINT IF EXISTS pedidos_data_pedido_obrigatoria;
ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedidos_data_pedido_obrigatoria CHECK (data_pedido IS NOT NULL);
ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  DROP CONSTRAINT IF EXISTS pedidos_cancelado_valor_zero;
ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedidos_cancelado_valor_zero CHECK (NOT cancelado OR valor_liquido = 0);

