-- TESTE 1: receita Gold igual à Silver e ao contrato financeiro do dataset.
WITH valores AS (
  SELECT
    (SELECT CAST(sum(receita) AS DECIMAL(22, 2)) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_gold,
    (SELECT CAST(sum(valor_liquido) AS DECIMAL(22, 2)) FROM lakehouse_rotaperfume.silver.pedidos) AS receita_silver
)
SELECT
  '01_receita_gold_igual_silver' AS nome_teste,
  concat('Gold=', receita_gold, '; Silver=', receita_silver) AS valor_calculado,
  'diferença <= 0.01 e contrato = 102303828.05' AS valor_esperado,
  CASE
    WHEN abs(receita_gold - receita_silver) <= 0.01
      AND abs(receita_gold - CAST(102303828.05 AS DECIMAL(22, 2))) <= 0.01
      AND abs(receita_silver - CAST(102303828.05 AS DECIMAL(22, 2))) <= 0.01
    THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: receita Gold=', receita_gold, ', Silver=', receita_silver))
  END AS status
FROM valores;

-- TESTE 2: CNPJ único na Silver.
WITH observado AS (
  SELECT count(*) - count(DISTINCT cnpj) AS cnpjs_duplicados
  FROM lakehouse_rotaperfume.silver.clientes
)
SELECT
  '02_cnpj_unico' AS nome_teste,
  CAST(cnpjs_duplicados AS STRING) AS valor_calculado,
  '0 CNPJs duplicados' AS valor_esperado,
  CASE
    WHEN cnpjs_duplicados = 0 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: encontrados ', cnpjs_duplicados, ' CNPJs duplicados'))
  END AS status
FROM observado;

-- TESTE 3: data do pedido obrigatória.
WITH observado AS (
  SELECT count_if(data_pedido IS NULL) AS datas_nulas
  FROM lakehouse_rotaperfume.silver.pedidos
)
SELECT
  '03_data_pedido_nao_nula' AS nome_teste,
  CAST(datas_nulas AS STRING) AS valor_calculado,
  '0 datas nulas' AS valor_esperado,
  CASE
    WHEN datas_nulas = 0 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: encontrados ', datas_nulas, ' pedidos sem data'))
  END AS status
FROM observado;

-- TESTE 4: receita negativa somente em devoluções.
WITH observado AS (
  SELECT count_if(receita < 0 AND NOT coalesce(devolucao, false)) AS receitas_negativas_invalidas
  FROM lakehouse_rotaperfume.gold.fato_vendas
)
SELECT
  '04_receita_negativa_somente_devolucao' AS nome_teste,
  CAST(receitas_negativas_invalidas AS STRING) AS valor_calculado,
  '0 receitas negativas fora de devoluções' AS valor_esperado,
  CASE
    WHEN receitas_negativas_invalidas = 0 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: encontradas ', receitas_negativas_invalidas, ' receitas negativas inválidas'))
  END AS status
FROM observado;

-- TESTE 5: volume da fato dentro do intervalo de sanidade.
WITH observado AS (
  SELECT count(*) AS linhas_fato
  FROM lakehouse_rotaperfume.gold.fato_vendas
)
SELECT
  '05_volume_fato' AS nome_teste,
  CAST(linhas_fato AS STRING) AS valor_calculado,
  'entre 140000 e 250000; referência seed 42 = 191080' AS valor_esperado,
  CASE
    WHEN linhas_fato BETWEEN 140000 AND 250000 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: volume da fato fora do intervalo: ', linhas_fato))
  END AS status
FROM observado;

-- TESTE 6: nenhum pedido órfão na fato.
WITH observado AS (
  SELECT count(*) AS pedidos_orfaos
  FROM lakehouse_rotaperfume.gold.fato_vendas AS fato
  LEFT JOIN lakehouse_rotaperfume.silver.pedidos AS pedidos
    ON fato.pedido_id = pedidos.pedido_id
  WHERE pedidos.pedido_id IS NULL
)
SELECT
  '06_pedido_orfao' AS nome_teste,
  CAST(pedidos_orfaos AS STRING) AS valor_calculado,
  '0 pedidos órfãos' AS valor_esperado,
  CASE
    WHEN pedidos_orfaos = 0 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: encontrados ', pedidos_orfaos, ' itens com pedido órfão'))
  END AS status
FROM observado;

-- TESTE 7: todo cliente canônico da fato existe na Silver.
WITH observado AS (
  SELECT count(*) AS clientes_orfaos
  FROM lakehouse_rotaperfume.gold.fato_vendas AS fato
  LEFT JOIN lakehouse_rotaperfume.silver.clientes AS clientes
    ON fato.cliente_id = clientes.cliente_id
  WHERE fato.cliente_id IS NULL OR clientes.cliente_id IS NULL
)
SELECT
  '07_cliente_canonico_orfao' AS nome_teste,
  CAST(clientes_orfaos AS STRING) AS valor_calculado,
  '0 clientes canônicos órfãos' AS valor_esperado,
  CASE
    WHEN clientes_orfaos = 0 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: encontrados ', clientes_orfaos, ' itens com cliente canônico órfão'))
  END AS status
FROM observado;

-- TESTE 8: mart de produto reconciliado com a fato.
WITH valores AS (
  SELECT
    (SELECT CAST(sum(receita) AS DECIMAL(22, 2)) FROM lakehouse_rotaperfume.gold.mart_produto_performance) AS receita_mart,
    (SELECT CAST(sum(receita) AS DECIMAL(22, 2)) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_fato
)
SELECT
  '08_mart_produto_conformado' AS nome_teste,
  concat('Mart=', receita_mart, '; Fato=', receita_fato) AS valor_calculado,
  'diferença <= 0.01' AS valor_esperado,
  CASE
    WHEN abs(receita_mart - receita_fato) <= 0.01 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: receita Mart=', receita_mart, ', Fato=', receita_fato))
  END AS status
FROM valores;

-- TESTE 9: CNPJ possui exatamente 14 dígitos.
WITH observado AS (
  SELECT count_if(cnpj IS NULL OR length(cnpj) <> 14 OR NOT (cnpj RLIKE '^[0-9]{14}$')) AS cnpjs_invalidos
  FROM lakehouse_rotaperfume.silver.clientes
)
SELECT
  '09_cnpj_14_digitos' AS nome_teste,
  CAST(cnpjs_invalidos AS STRING) AS valor_calculado,
  '0 CNPJs inválidos' AS valor_esperado,
  CASE
    WHEN cnpjs_invalidos = 0 THEN 'PASSOU'
    ELSE raise_error(concat('FALHOU: encontrados ', cnpjs_invalidos, ' CNPJs inválidos'))
  END AS status
FROM observado;
