-- CONTRATO DA FATO_VENDAS
-- GRANULARIDADE: uma linha por item de pedido.
-- CONSUMIDORES: Diretorias Comercial, Produto e Financeira; BI e IA/Genie.
-- FILTRO: somente pedidos com cancelado = true são excluídos.
-- DEVOLUÇÕES: não são excluídas; mantêm quantidade e receita negativas e devolucao = true.
-- MÉTRICAS: receita = quantidade * preço praticado; custo = quantidade * custo unitário;
-- margem = receita - custo. Frete e descontos comerciais não são inventados.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas
USING DELTA
PARTITIONED BY (ano, mes)
AS
WITH mapa_cliente AS (
  SELECT
    clientes.cliente_id AS cliente_id_canonico,
    cliente_id_historico
  FROM lakehouse_rotaperfume.silver.clientes AS clientes
  LATERAL VIEW explode(
    array_union(
      array(clientes.cliente_id),
      coalesce(clientes.cliente_ids_duplicados, CAST(array() AS ARRAY<BIGINT>))
    )
  ) ids AS cliente_id_historico
),
vendas_conformadas AS (
  SELECT
    itens.item_id,
    pedidos.pedido_id,
    pedidos.data_pedido,
    pedidos.canal,
    mapa.cliente_id_canonico AS cliente_id,
    clientes.razao_social,
    clientes.segmento,
    clientes.cidade,
    clientes.uf,
    pedidos.vendedor_id,
    itens.sku,
    produtos.categoria,
    produtos.marca,
    produtos.nota_olfativa,
    itens.quantidade,
    itens.preco_praticado,
    CAST(itens.quantidade * itens.preco_praticado AS DECIMAL(20, 2)) AS receita,
    CAST(itens.quantidade * produtos.custo_unitario AS DECIMAL(20, 2)) AS custo,
    itens.devolucao,
    year(pedidos.data_pedido) AS ano,
    month(pedidos.data_pedido) AS mes
  FROM lakehouse_rotaperfume.silver.itens_pedido AS itens
  INNER JOIN lakehouse_rotaperfume.silver.pedidos AS pedidos
    ON itens.pedido_id = pedidos.pedido_id
  LEFT JOIN mapa_cliente AS mapa
    ON pedidos.cliente_id = mapa.cliente_id_historico
  LEFT JOIN lakehouse_rotaperfume.silver.clientes AS clientes
    ON mapa.cliente_id_canonico = clientes.cliente_id
  LEFT JOIN lakehouse_rotaperfume.silver.produtos AS produtos
    ON itens.sku = produtos.sku
  WHERE NOT (pedidos.cancelado <=> true)
)
SELECT
  item_id,
  pedido_id,
  data_pedido,
  canal,
  cliente_id,
  razao_social,
  segmento,
  cidade,
  uf,
  vendedor_id,
  sku,
  categoria,
  marca,
  nota_olfativa,
  quantidade,
  preco_praticado,
  receita,
  custo,
  CAST(receita - custo AS DECIMAL(20, 2)) AS margem,
  devolucao,
  current_timestamp() AS _processado_em,
  ano,
  mes
FROM vendas_conformadas;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fato_vendas IS
  'Fonte conformada de vendas no grão de item, sem pedidos cancelados e com devoluções preservadas.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN item_id COMMENT
  'Identificador único do item que define o grão da fato.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN pedido_id COMMENT
  'Pedido comercial ao qual o item pertence.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN data_pedido COMMENT
  'Data em que o pedido do item foi realizado.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN canal COMMENT
  'Canal comercial pelo qual o pedido foi registrado.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cliente_id COMMENT
  'Identificador canônico do cliente, resolvido a partir de IDs atuais e históricos.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN razao_social COMMENT
  'Razão social normalizada do cliente canônico associado à venda.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN segmento COMMENT
  'Segmento comercial atribuído ao cliente canônico.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cidade COMMENT
  'Cidade do cliente canônico no momento da modelagem Gold.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN uf COMMENT
  'Unidade federativa do cliente canônico no momento da modelagem Gold.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN vendedor_id COMMENT
  'Vendedor responsável pelo pedido, preservado mesmo quando não houver dimensão correspondente.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN sku COMMENT
  'SKU vendido no item do pedido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN categoria COMMENT
  'Categoria comercial do produto vendido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN marca COMMENT
  'Marca do produto vendido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN nota_olfativa COMMENT
  'Nota olfativa principal do produto vendido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN quantidade COMMENT
  'Quantidade do item; valores negativos representam devoluções.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN preco_praticado COMMENT
  'Preço unitário efetivamente registrado no item do pedido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN receita COMMENT
  'Quantidade multiplicada pelo preço praticado; negativa em devoluções.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN custo COMMENT
  'Quantidade multiplicada pelo custo unitário; negativo em devoluções.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN margem COMMENT
  'Receita menos custo do produto. Não considera desconto comercial nem frete.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN devolucao COMMENT
  'Indica item devolvido, preservado na fato com quantidade, receita e custo negativos.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN _processado_em COMMENT
  'Momento em que a linha foi materializada na camada Gold.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN ano COMMENT
  'Ano da data do pedido, usado também no particionamento físico.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN mes COMMENT
  'Mês da data do pedido, usado também no particionamento físico.';

