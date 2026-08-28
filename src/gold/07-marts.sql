-- mart_vendas_por_vendedor
-- CONSUMIDOR: Diretoria Comercial.
-- GRANULARIDADE: vendedor por ano e mês do pedido.
-- BASE: gold.fato_vendas, garantindo a mesma definição conformada de receita e margem.
-- REGRAS: atingimento = 100 * receita / meta; ticket médio = receita / pedidos distintos.
-- Vendedores sem dimensão são preservados como não identificados para não alterar a receita total.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor AS
WITH vendas_vendedor AS (
  SELECT
    fato.ano,
    fato.mes,
    fato.vendedor_id,
    coalesce(vendedores.nome, 'Vendedor não identificado') AS nome_vendedor,
    coalesce(vendedores.regiao, 'Região não identificada') AS regiao,
    CAST(sum(fato.receita) AS DECIMAL(22, 2)) AS receita,
    CAST(sum(fato.margem) AS DECIMAL(22, 2)) AS margem,
    max(vendedores.meta_mensal) AS meta,
    count(DISTINCT fato.cliente_id) AS clientes_atendidos,
    count(DISTINCT fato.pedido_id) AS pedidos_atendidos
  FROM lakehouse_rotaperfume.gold.fato_vendas AS fato
  LEFT JOIN lakehouse_rotaperfume.gold.dim_vendedor AS vendedores
    ON fato.vendedor_id = vendedores.vendedor_id
  GROUP BY
    fato.ano,
    fato.mes,
    fato.vendedor_id,
    coalesce(vendedores.nome, 'Vendedor não identificado'),
    coalesce(vendedores.regiao, 'Região não identificada')
)
SELECT
  ano,
  mes,
  vendedor_id,
  nome_vendedor,
  regiao,
  receita,
  margem,
  meta,
  CASE
    WHEN meta IS NULL OR meta = 0 THEN NULL
    ELSE CAST(100 * receita / meta AS DECIMAL(18, 4))
  END AS atingimento,
  clientes_atendidos,
  CASE
    WHEN pedidos_atendidos = 0 THEN NULL
    ELSE CAST(receita / pedidos_atendidos AS DECIMAL(18, 2))
  END AS ticket_medio,
  current_timestamp() AS _processado_em
FROM vendas_vendedor;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor IS
  'Mart comercial no grão vendedor por mês, reconciliável com a receita da fato de vendas.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN receita COMMENT
  'Receita líquida dos itens, incluindo devoluções e excluindo pedidos cancelados.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN margem COMMENT
  'Receita menos custo dos produtos vendidos pelo vendedor no mês.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN meta COMMENT
  'Meta mensal vigente no cadastro analítico do vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN atingimento COMMENT
  'Percentual de atingimento calculado como 100 vezes receita dividida pela meta; nulo sem meta válida.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN clientes_atendidos COMMENT
  'Quantidade de clientes canônicos distintos atendidos pelo vendedor no mês.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN ticket_medio COMMENT
  'Receita do vendedor dividida pela quantidade de pedidos distintos no mês.';

-- mart_produto_performance
-- CONSUMIDOR: Diretoria de Produto.
-- GRANULARIDADE: SKU por ano e mês do pedido.
-- BASE: gold.fato_vendas, sem redefinir receita, custo ou margem.
-- CURVA ABC: ordena SKU por receita líquida decrescente dentro de cada mês;
-- participação acumulada até 80% = A, acima de 80% até 95% = B, restante = C.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance AS
WITH produtos_mes AS (
  SELECT
    fato.ano,
    fato.mes,
    fato.sku,
    max(produtos.descricao) AS produto,
    max(fato.marca) AS marca,
    max(fato.categoria) AS categoria,
    CAST(sum(fato.receita) AS DECIMAL(22, 2)) AS receita,
    CAST(sum(fato.margem) AS DECIMAL(22, 2)) AS margem,
    sum(fato.quantidade) AS quantidade
  FROM lakehouse_rotaperfume.gold.fato_vendas AS fato
  LEFT JOIN lakehouse_rotaperfume.gold.dim_produto AS produtos
    ON fato.sku = produtos.sku
  GROUP BY fato.ano, fato.mes, fato.sku
),
participacoes AS (
  SELECT
    *,
    sum(receita) OVER (PARTITION BY ano, mes) AS receita_total_mes,
    sum(receita) OVER (
      PARTITION BY ano, mes
      ORDER BY receita DESC, sku
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS receita_acumulada_mes
  FROM produtos_mes
)
SELECT
  ano,
  mes,
  sku,
  produto,
  marca,
  categoria,
  receita,
  margem,
  CASE
    WHEN receita = 0 THEN NULL
    ELSE CAST(100 * margem / receita AS DECIMAL(18, 4))
  END AS margem_pct,
  quantidade,
  CASE
    WHEN receita_total_mes = 0 THEN 'C'
    WHEN receita_acumulada_mes / receita_total_mes <= 0.80 THEN 'A'
    WHEN receita_acumulada_mes / receita_total_mes <= 0.95 THEN 'B'
    ELSE 'C'
  END AS curva_abc,
  current_timestamp() AS _processado_em
FROM participacoes;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_produto_performance IS
  'Mart de produto no grão SKU por mês, baseado integralmente na fato de vendas conformada.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN receita COMMENT
  'Receita líquida do SKU no mês, incluindo o efeito financeiro das devoluções.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN margem COMMENT
  'Receita menos custo do SKU no mês, conforme a fato de vendas.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN margem_pct COMMENT
  'Percentual calculado como 100 vezes margem dividida pela receita; nulo quando a receita é zero.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN quantidade COMMENT
  'Quantidade líquida do SKU, mantendo devoluções como valores negativos.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN curva_abc COMMENT
  'Classificação mensal por receita acumulada: A até 80%, B acima de 80% até 95%, C no restante.';

-- mart_financeiro_recebimento
-- CONSUMIDOR: Diretoria Financeira.
-- GRANULARIDADE: ano e mês de vencimento do pagamento.
-- BASE: silver.pagamentos diretamente no grão de pagamento, sem join com itens de venda.
-- MÉTRICAS: a receber = valor nominal; recebido = valor líquido com data de pagamento;
-- atraso = dias positivos entre pagamento e vencimento; custo de taxa = valor menos valor líquido.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento AS
SELECT
  year(data_vencimento) AS ano,
  month(data_vencimento) AS mes,
  CAST(sum(valor) AS DECIMAL(22, 2)) AS valor_a_receber,
  CAST(sum(CASE WHEN data_pagamento IS NOT NULL THEN valor_liquido ELSE 0 END) AS DECIMAL(22, 2)) AS valor_recebido,
  CAST(
    avg(
      CASE
        WHEN data_pagamento IS NULL THEN NULL
        ELSE greatest(datediff(data_pagamento, data_vencimento), 0)
      END
    ) AS DECIMAL(18, 2)
  ) AS atraso_medio_dias,
  CAST(sum(valor - valor_liquido) AS DECIMAL(22, 2)) AS custo_taxa,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.pagamentos
GROUP BY year(data_vencimento), month(data_vencimento);

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento IS
  'Mart financeiro no grão mês de vencimento, calculado sem multiplicação por itens de pedido.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN valor_a_receber COMMENT
  'Soma do valor nominal dos pagamentos com vencimento no mês.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN valor_recebido COMMENT
  'Soma do valor líquido dos pagamentos que possuem data de pagamento.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN atraso_medio_dias COMMENT
  'Média de dias de atraso dos pagamentos realizados; pagamentos antecipados contribuem com zero.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN custo_taxa COMMENT
  'Diferença agregada entre valor nominal e valor líquido dos pagamentos.';

