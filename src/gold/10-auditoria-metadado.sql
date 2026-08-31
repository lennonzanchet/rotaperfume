-- A auditoria cobre todos os objetos Gold e interrompe o pipeline quando a
-- interface semântica não estiver integralmente documentada.

WITH objetos_sem_comentario AS (
  SELECT table_name
  FROM lakehouse_rotaperfume.information_schema.tables
  WHERE table_schema = 'gold'
    AND (comment IS NULL OR trim(comment) = '')
)
SELECT CASE
  WHEN count(*) = 0 THEN 'PASSOU: todos os objetos Gold possuem COMMENT.'
  ELSE raise_error(concat('Metadata Gold incompleta: objetos sem COMMENT = ', concat_ws(', ', sort_array(collect_list(table_name)))))
END AS auditoria_objetos
FROM objetos_sem_comentario;

WITH colunas_fato_sem_comentario AS (
  SELECT column_name
  FROM lakehouse_rotaperfume.information_schema.columns
  WHERE table_schema = 'gold'
    AND table_name = 'fato_vendas'
    AND (comment IS NULL OR trim(comment) = '')
)
SELECT CASE
  WHEN count(*) = 0 THEN 'PASSOU: fato_vendas possui COMMENT em todas as colunas.'
  ELSE raise_error(concat('Metadata da fato_vendas incompleta: ', concat_ws(', ', sort_array(collect_list(column_name)))))
END AS auditoria_fato
FROM colunas_fato_sem_comentario;

WITH views_obrigatorias AS (
  SELECT explode(array(
    'clientes_em_risco',
    'efeito_lancamento',
    'margem_por_categoria',
    'ranking_marcas',
    'receita_mensal',
    'ruptura_por_marca'
  )) AS table_name
),
views_ausentes AS (
  SELECT views.table_name
  FROM views_obrigatorias AS views
  LEFT JOIN lakehouse_rotaperfume.information_schema.tables AS objetos
    ON objetos.table_schema = 'gold'
   AND objetos.table_name = views.table_name
  WHERE objetos.table_name IS NULL
)
SELECT CASE
  WHEN count(*) = 0 THEN 'PASSOU: as seis views obrigatorias existem.'
  ELSE raise_error(concat(
    'Views Gold obrigatorias ausentes: ',
    concat_ws(', ', sort_array(collect_list(table_name)))
  ))
END AS auditoria_existencia_views
FROM views_ausentes;

WITH views_obrigatorias AS (
  SELECT explode(array(
    'clientes_em_risco',
    'efeito_lancamento',
    'margem_por_categoria',
    'ranking_marcas',
    'receita_mensal',
    'ruptura_por_marca'
  )) AS table_name
),
colunas_views_sem_comentario AS (
  SELECT colunas.table_name, colunas.column_name
  FROM lakehouse_rotaperfume.information_schema.columns AS colunas
  INNER JOIN views_obrigatorias AS views
    ON colunas.table_name = views.table_name
  WHERE colunas.table_schema = 'gold'
    AND (colunas.comment IS NULL OR trim(colunas.comment) = '')
)
SELECT CASE
  WHEN count(*) = 0 THEN 'PASSOU: as seis views possuem COMMENT em todas as colunas.'
  ELSE raise_error(concat(
    'Metadata das views incompleta: ',
    concat_ws(', ', sort_array(collect_list(concat(table_name, '.', column_name))))
  ))
END AS auditoria_views
FROM colunas_views_sem_comentario;

-- Contrato ampliado: como 09-metricas-negocio.sql completa a metadata das
-- tabelas existentes, qualquer coluna Gold sem comentário também é falha.
WITH colunas_gold_sem_comentario AS (
  SELECT table_name, column_name
  FROM lakehouse_rotaperfume.information_schema.columns
  WHERE table_schema = 'gold'
    AND (comment IS NULL OR trim(comment) = '')
)
SELECT CASE
  WHEN count(*) = 0 THEN 'PASSOU: cobertura de comentários das colunas Gold = 100%.'
  ELSE raise_error(concat(
    'Cobertura Gold inferior a 100%: ',
    concat_ws(', ', sort_array(collect_list(concat(table_name, '.', column_name))))
  ))
END AS auditoria_cobertura_total
FROM colunas_gold_sem_comentario;

SELECT
  tabelas.table_name,
  count(colunas.column_name) AS total_colunas,
  count_if(colunas.comment IS NOT NULL AND trim(colunas.comment) <> '') AS colunas_comentadas,
  CAST(
    100.0 * count_if(colunas.comment IS NOT NULL AND trim(colunas.comment) <> '')
      / NULLIF(count(colunas.column_name), 0)
    AS DECIMAL(7, 2)
  ) AS cobertura_pct
FROM lakehouse_rotaperfume.information_schema.tables AS tabelas
LEFT JOIN lakehouse_rotaperfume.information_schema.columns AS colunas
  ON tabelas.table_catalog = colunas.table_catalog
 AND tabelas.table_schema = colunas.table_schema
 AND tabelas.table_name = colunas.table_name
WHERE tabelas.table_schema = 'gold'
GROUP BY tabelas.table_name
ORDER BY tabelas.table_name;
