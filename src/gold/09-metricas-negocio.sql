-- Views semânticas para consumo por BI e Genie.

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.receita_mensal (
  ano COMMENT 'Ano civil da venda.',
  mes COMMENT 'Número do mês civil da venda, de 1 a 12.',
  receita COMMENT 'Receita líquida mensal, incluindo devoluções e excluindo pedidos cancelados.',
  margem COMMENT 'Receita mensal menos o custo dos produtos vendidos.',
  pedidos COMMENT 'Quantidade de pedidos válidos distintos no mês.',
  ticket_medio COMMENT 'Receita mensal dividida pela quantidade de pedidos distintos.',
  mes_pico_setor COMMENT 'Indica abril, junho ou outubro, meses de pico comercial definidos para o setor.'
)
COMMENT 'Responde como receita, margem e quantidade de pedidos evoluem mês a mês e identifica os meses de pico do setor.'
AS
SELECT
  vendas.ano,
  vendas.mes,
  CAST(sum(vendas.receita) AS DECIMAL(22, 2)) AS receita,
  CAST(sum(vendas.margem) AS DECIMAL(22, 2)) AS margem,
  count(DISTINCT vendas.pedido_id) AS pedidos,
  CAST(sum(vendas.receita) / NULLIF(count(DISTINCT vendas.pedido_id), 0) AS DECIMAL(18, 2)) AS ticket_medio,
  bool_or(calendario.mes_pico_setor) AS mes_pico_setor
FROM lakehouse_rotaperfume.gold.fato_vendas AS vendas
INNER JOIN lakehouse_rotaperfume.gold.dim_calendario AS calendario
  ON vendas.data_pedido = calendario.data
GROUP BY vendas.ano, vendas.mes;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ranking_marcas (
  marca COMMENT 'Marca comercial dos produtos vendidos.',
  receita COMMENT 'Receita líquida da marca, incluindo devoluções.',
  margem COMMENT 'Receita da marca menos o custo dos produtos vendidos.',
  margem_pct COMMENT 'Margem dividida pela receita da marca, em escala de zero a um.',
  participacao_pct COMMENT 'Participação da marca na receita líquida total, em escala de zero a um.'
)
COMMENT 'Responde quais marcas mais vendem, qual margem cada marca gera e sua participação na receita total.'
AS
WITH marcas AS (
  SELECT
    marca,
    sum(receita) AS receita,
    sum(margem) AS margem
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY marca
)
SELECT
  marca,
  CAST(receita AS DECIMAL(22, 2)) AS receita,
  CAST(margem AS DECIMAL(22, 2)) AS margem,
  CAST(margem / NULLIF(receita, 0) AS DECIMAL(18, 6)) AS margem_pct,
  CAST(receita / NULLIF(sum(receita) OVER (), 0) AS DECIMAL(18, 6)) AS participacao_pct
FROM marcas;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.margem_por_categoria (
  categoria COMMENT 'Categoria comercial do produto vendido.',
  receita COMMENT 'Receita líquida da categoria, incluindo devoluções.',
  margem COMMENT 'Receita da categoria menos o custo dos produtos vendidos.',
  margem_pct COMMENT 'Margem dividida pela receita da categoria, em escala de zero a um.'
)
COMMENT 'Responde quais categorias possuem maior e menor margem e qual receita sustenta essa rentabilidade.'
AS
SELECT
  categoria,
  CAST(sum(receita) AS DECIMAL(22, 2)) AS receita,
  CAST(sum(margem) AS DECIMAL(22, 2)) AS margem,
  CAST(sum(margem) / NULLIF(sum(receita), 0) AS DECIMAL(18, 6)) AS margem_pct
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY categoria;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.clientes_em_risco (
  cliente_id COMMENT 'Identificador canônico do cliente.',
  cnpj COMMENT 'CNPJ normalizado do cliente com 14 dígitos.',
  razao_social COMMENT 'Razão social normalizada do cliente.',
  segmento COMMENT 'Segmento comercial do cliente.',
  cidade COMMENT 'Cidade do cliente.',
  uf COMMENT 'Unidade federativa do cliente.',
  data_ultimo_pedido COMMENT 'Data do pedido válido mais recente do cliente.',
  dias_sem_comprar COMMENT 'Quantidade de dias desde o último pedido válido.',
  receita_acumulada COMMENT 'Receita líquida acumulada do cliente no período observado.',
  receita_mensal_anterior COMMENT 'Receita acumulada dividida pelos meses do período observado, estimando a contribuição mensal histórica interrompida.'
)
COMMENT 'Responde quais clientes estão há mais de 90 dias sem comprar e quanta receita mensal histórica estava associada a eles.'
AS
WITH periodo AS (
  SELECT
    greatest(
      CAST(floor(months_between(max(data_pedido), min(data_pedido))) AS INT) + 1,
      1
    ) AS meses_observados
  FROM lakehouse_rotaperfume.gold.fato_vendas
)
SELECT
  clientes.cliente_id,
  clientes.cnpj,
  clientes.razao_social,
  clientes.segmento,
  clientes.cidade,
  clientes.uf,
  clientes.data_ultimo_pedido,
  clientes.dias_sem_comprar,
  clientes.receita_acumulada,
  CAST(clientes.receita_acumulada / periodo.meses_observados AS DECIMAL(18, 2)) AS receita_mensal_anterior
FROM lakehouse_rotaperfume.gold.dim_cliente AS clientes
CROSS JOIN periodo
WHERE clientes.dias_sem_comprar > 90;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.efeito_lancamento (
  sku COMMENT 'Identificador comercial do produto.',
  produto COMMENT 'Descrição comercial do produto.',
  marca COMMENT 'Marca comercial do produto.',
  categoria COMMENT 'Categoria comercial do produto.',
  data_lancamento COMMENT 'Data de lançamento cadastrada para o produto.',
  receita_primeiros_120_dias COMMENT 'Receita líquida entre o lançamento e o 119º dia posterior.',
  receita_apos_120_dias COMMENT 'Receita líquida a partir do 120º dia posterior ao lançamento.',
  receita_total_pos_lancamento COMMENT 'Receita líquida total registrada a partir da data de lançamento.'
)
COMMENT 'Responde como cada produto performa nos primeiros 120 dias após o lançamento em comparação com o restante do período.'
AS
SELECT
  produtos.sku,
  produtos.descricao AS produto,
  produtos.marca,
  produtos.categoria,
  produtos.data_lancamento,
  CAST(sum(CASE WHEN datediff(vendas.data_pedido, produtos.data_lancamento) BETWEEN 0 AND 119 THEN vendas.receita ELSE 0 END) AS DECIMAL(22, 2)) AS receita_primeiros_120_dias,
  CAST(sum(CASE WHEN datediff(vendas.data_pedido, produtos.data_lancamento) >= 120 THEN vendas.receita ELSE 0 END) AS DECIMAL(22, 2)) AS receita_apos_120_dias,
  CAST(sum(CASE WHEN vendas.data_pedido >= produtos.data_lancamento THEN vendas.receita ELSE 0 END) AS DECIMAL(22, 2)) AS receita_total_pos_lancamento
FROM lakehouse_rotaperfume.gold.dim_produto AS produtos
LEFT JOIN lakehouse_rotaperfume.gold.fato_vendas AS vendas
  ON produtos.sku = vendas.sku
GROUP BY produtos.sku, produtos.descricao, produtos.marca, produtos.categoria, produtos.data_lancamento;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ruptura_por_marca (
  marca COMMENT 'Marca comercial associada ao SKU observado no estoque.',
  total_snapshots COMMENT 'Quantidade de snapshots de estoque observados para a marca.',
  snapshots_ruptura COMMENT 'Quantidade de snapshots com saldo igual a zero.',
  ruptura_pct COMMENT 'Proporção de snapshots com saldo igual a zero, em escala de zero a um.'
)
COMMENT 'Responde quais marcas sofrem mais com ruptura de estoque pelo percentual de snapshots com saldo igual a zero.'
AS
SELECT
  produtos.marca,
  count(*) AS total_snapshots,
  count_if(estoque.saldo = 0) AS snapshots_ruptura,
  CAST(count_if(estoque.saldo = 0) / NULLIF(count(*), 0) AS DECIMAL(18, 6)) AS ruptura_pct
FROM lakehouse_rotaperfume.silver.estoque AS estoque
INNER JOIN lakehouse_rotaperfume.gold.dim_produto AS produtos
  ON estoque.sku = produtos.sku
GROUP BY produtos.marca;

-- Completa a metadata das tabelas Gold existentes para que toda a interface
-- semântica entregue ao Genie tenha cobertura de comentários igual a 100%.
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN cliente_id COMMENT 'Identificador canônico do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN cnpj COMMENT 'CNPJ normalizado do cliente com 14 dígitos.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN razao_social COMMENT 'Razão social normalizada do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN segmento COMMENT 'Segmento comercial do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN cidade COMMENT 'Cidade do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN uf COMMENT 'Unidade federativa do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN data_cadastro COMMENT 'Data de cadastro do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN ativo COMMENT 'Indica cliente ativo no cadastro comercial.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN _processado_em COMMENT 'Momento de materialização da dimensão Gold.';

ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN sku COMMENT 'Identificador comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN descricao COMMENT 'Descrição comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN marca COMMENT 'Marca comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN categoria COMMENT 'Categoria comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN nota_olfativa COMMENT 'Nota olfativa principal do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN custo_unitario COMMENT 'Custo unitário do produto usado no cálculo de margem.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN preco_tabela COMMENT 'Preço comercial de tabela do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN unidade COMMENT 'Unidade comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN data_lancamento COMMENT 'Data de lançamento do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN ativo COMMENT 'Indica produto ativo no cadastro.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN _processado_em COMMENT 'Momento de materialização da dimensão Gold.';

ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN vendedor_id COMMENT 'Identificador do vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN nome COMMENT 'Nome do vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN regiao COMMENT 'Região comercial atendida pelo vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN uf COMMENT 'Unidade federativa associada ao vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN data_admissao COMMENT 'Data de admissão do vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN data_desligamento COMMENT 'Data de desligamento, nula enquanto o vínculo estiver ativo.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN _processado_em COMMENT 'Momento de materialização da dimensão Gold.';

ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN data COMMENT 'Data civil representada pela linha.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN ano COMMENT 'Ano civil da data.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN mes COMMENT 'Número do mês civil, de 1 a 12.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN nome_mes COMMENT 'Nome do mês da data.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN trimestre COMMENT 'Trimestre civil da data.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN dia_mes COMMENT 'Dia do mês da data.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN nome_dia_semana COMMENT 'Nome do dia da semana.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN _processado_em COMMENT 'Momento de materialização da dimensão Gold.';

ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN ano COMMENT 'Ano civil da venda.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN mes COMMENT 'Número do mês civil da venda.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN vendedor_id COMMENT 'Identificador do vendedor responsável.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN nome_vendedor COMMENT 'Nome do vendedor ou indicação de vendedor não identificado.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN regiao COMMENT 'Região comercial do vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN _processado_em COMMENT 'Momento de materialização do mart Gold.';

ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN ano COMMENT 'Ano civil da venda.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN mes COMMENT 'Número do mês civil da venda.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN sku COMMENT 'Identificador comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN produto COMMENT 'Descrição comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN marca COMMENT 'Marca comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN categoria COMMENT 'Categoria comercial do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN _processado_em COMMENT 'Momento de materialização do mart Gold.';

ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN ano COMMENT 'Ano do vencimento do pagamento.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN mes COMMENT 'Mês do vencimento do pagamento.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN _processado_em COMMENT 'Momento de materialização do mart Gold.';
