-- dim_cliente
-- Granularidade: uma linha por cliente canônico da Silver.
-- Consumidores: BI comercial, CRM analítico e segmentações de clientes.
-- Regras: IDs históricos são mapeados ao cliente canônico; somente pedidos não cancelados
-- alimentam datas, quantidade de pedidos e receita acumulada.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente AS
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
metricas_pedidos AS (
  SELECT
    mapa.cliente_id_canonico AS cliente_id,
    min(pedidos.data_pedido) AS data_primeiro_pedido,
    max(pedidos.data_pedido) AS data_ultimo_pedido,
    count(DISTINCT pedidos.pedido_id) AS total_pedidos,
    CAST(sum(pedidos.valor_liquido) AS DECIMAL(20, 2)) AS receita_acumulada
  FROM mapa_cliente AS mapa
  INNER JOIN lakehouse_rotaperfume.silver.pedidos AS pedidos
    ON mapa.cliente_id_historico = pedidos.cliente_id
  WHERE NOT (pedidos.cancelado <=> true)
  GROUP BY mapa.cliente_id_canonico
)
SELECT
  clientes.cliente_id,
  clientes.cnpj,
  clientes.razao_social,
  clientes.segmento,
  clientes.cidade,
  clientes.uf,
  clientes.data_cadastro,
  clientes.ativo,
  clientes.cliente_ids_duplicados,
  metricas.data_primeiro_pedido,
  metricas.data_ultimo_pedido,
  coalesce(metricas.total_pedidos, 0) AS total_pedidos,
  coalesce(metricas.receita_acumulada, CAST(0 AS DECIMAL(20, 2))) AS receita_acumulada,
  CASE
    WHEN metricas.data_ultimo_pedido IS NULL THEN NULL
    ELSE datediff(current_date(), metricas.data_ultimo_pedido)
  END AS dias_sem_comprar,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.clientes AS clientes
LEFT JOIN metricas_pedidos AS metricas
  ON clientes.cliente_id = metricas.cliente_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_cliente IS
  'Dimensão de clientes canônicos enriquecida com métricas de pedidos não cancelados.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN cliente_ids_duplicados COMMENT
  'IDs históricos consolidados no cliente canônico e usados para preservar suas vendas.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN data_primeiro_pedido COMMENT
  'Primeira data de pedido não cancelado considerando todos os IDs históricos do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN data_ultimo_pedido COMMENT
  'Última data de pedido não cancelado considerando todos os IDs históricos do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN total_pedidos COMMENT
  'Quantidade distinta de pedidos não cancelados atribuídos ao cliente canônico.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN receita_acumulada COMMENT
  'Soma do valor líquido dos pedidos não cancelados atribuídos ao cliente canônico.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN dias_sem_comprar COMMENT
  'Dias desde o último pedido não cancelado; nulo quando o cliente nunca realizou pedido.';

-- dim_produto
-- Granularidade: uma linha por SKU.
-- Consumidores: BI de Produto, análises de margem e sortimento.
-- Regra: descontinuado é a representação analítica de produto não ativo.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto AS
SELECT
  sku,
  descricao,
  marca,
  categoria,
  nota_olfativa,
  custo_unitario,
  preco_tabela,
  unidade,
  data_lancamento,
  ativo,
  coalesce(NOT ativo, false) AS descontinuado,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_produto IS
  'Dimensão analítica de produtos no grão de SKU, com situação de descontinuação.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN descontinuado COMMENT
  'Indica que o produto não está mais ativo no cadastro comercial.';

-- dim_vendedor
-- Granularidade: uma linha por vendedor.
-- Consumidores: Diretoria Comercial e acompanhamento de metas.
-- Regra: ativo considera a data de desligamento em relação à data atual.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor AS
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  data_admissao,
  data_desligamento,
  meta_mensal,
  data_desligamento IS NULL OR data_desligamento > current_date() AS ativo,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_vendedor IS
  'Dimensão de vendedores com meta mensal e situação de vínculo calculada.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN ativo COMMENT
  'Indica vendedor sem desligamento efetivo até a data atual.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN meta_mensal COMMENT
  'Meta mensal de receita usada no cálculo de atingimento comercial.';

-- dim_calendario
-- Granularidade: uma linha por dia entre a menor e a maior data de pedido Silver.
-- Consumidores: todos os painéis com análise temporal.
-- Regra: abril, junho e outubro são meses de pico do setor no contexto do projeto.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario AS
WITH limites AS (
  SELECT
    min(data_pedido) AS data_minima,
    max(data_pedido) AS data_maxima
  FROM lakehouse_rotaperfume.silver.pedidos
),
datas AS (
  SELECT explode(sequence(data_minima, data_maxima, INTERVAL 1 DAY)) AS data
  FROM limites
)
SELECT
  data,
  year(data) AS ano,
  month(data) AS mes,
  date_format(data, 'MMMM') AS nome_mes,
  quarter(data) AS trimestre,
  day(data) AS dia_mes,
  dayofweek(data) AS dia_semana,
  date_format(data, 'EEEE') AS nome_dia_semana,
  month(data) IN (4, 6, 10) AS mes_pico_setor,
  current_timestamp() AS _processado_em
FROM datas;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_calendario IS
  'Calendário conformado para o período real de pedidos do projeto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN mes_pico_setor COMMENT
  'Marca abril, junho e outubro como meses de pico definidos pelo contexto comercial do projeto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN dia_semana COMMENT
  'Número do dia da semana conforme convenção Spark: domingo igual a 1.';

