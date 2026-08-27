# Databricks notebook source

import re

from pyspark.sql import functions as F
from pyspark.sql.types import StringType


dbutils.widgets.text("catalog", "lakehouse_rotaperfume", "Catálogo")
catalog = dbutils.widgets.get("catalog").strip()

if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", catalog):
    raise ValueError(f"Nome de catálogo inválido: {catalog!r}")

tabelas = [
    ("ERP", "produtos"),
    ("ERP", "pedidos"),
    ("ERP", "itens_pedido"),
    ("ERP", "pagamentos"),
    ("ERP", "estoque"),
    ("CRM", "clientes"),
    ("CRM", "vendedores"),
    ("CRM", "carteira"),
    ("CRM", "oportunidades"),
    ("CRM", "visitas"),
]

arquivos_esperados = [f"{tabela}.csv" for _, tabela in tabelas]
tabela_controle = f"`{catalog}`.`bronze`.`_raw_arquivos`"

linhas_controle = (
    spark.table(tabela_controle)
    .filter(F.col("arquivo").isin(arquivos_esperados))
    .select("arquivo", "linhas")
    .collect()
)

contagens_raw = {}
duplicados = set()

for registro in linhas_controle:
    arquivo = registro["arquivo"]
    if arquivo in contagens_raw:
        duplicados.add(arquivo)
    contagens_raw[arquivo] = int(registro["linhas"])

ausentes = sorted(set(arquivos_esperados) - set(contagens_raw))
if ausentes or duplicados:
    detalhes = []
    if ausentes:
        detalhes.append(f"arquivos ausentes no controle Raw: {', '.join(ausentes)}")
    if duplicados:
        detalhes.append(f"arquivos duplicados no controle Raw: {', '.join(sorted(duplicados))}")
    raise RuntimeError("Controle Raw inválido: " + "; ".join(detalhes))


def ingerir_tabela(sistema: str, tabela: str) -> dict:
    arquivo = f"{tabela}.csv"
    origem = f"/Volumes/{catalog}/bronze/raw/{sistema.lower()}/{arquivo}"
    destino = f"`{catalog}`.`bronze`.`{tabela}`"

    dados_origem = (
        spark.read.option("header", "true")
        .option("inferSchema", "false")
        .option("multiLine", "false")
        .csv(origem)
    )

    colunas_tecnicas_inesperadas = [coluna for coluna in dados_origem.columns if coluna.startswith("_")]
    colunas_negocio = [coluna for coluna in dados_origem.columns if coluna not in colunas_tecnicas_inesperadas]

    if not colunas_negocio:
        raise RuntimeError(f"Nenhuma coluna de negócio encontrada em {origem}.")

    tipos_invalidos = [
        campo.name
        for campo in dados_origem.schema.fields
        if campo.name in colunas_negocio and not isinstance(campo.dataType, StringType)
    ]
    if tipos_invalidos:
        raise RuntimeError(
            f"As colunas de negócio devem ser STRING em {arquivo}: {', '.join(tipos_invalidos)}"
        )

    dados_bronze = dados_origem.select(*colunas_negocio).withColumns(
        {
            "_ingerido_em": F.current_timestamp(),
            "_arquivo_origem": F.lit(arquivo).cast("string"),
        }
    )

    (
        dados_bronze.write.format("delta")
        .mode("overwrite")
        .option("overwriteSchema", "true")
        .saveAsTable(destino)
    )

    spark.sql(
        f"COMMENT ON TABLE {destino} IS "
        f"'Dados brutos de {tabela} recebidos do sistema {sistema}.'"
    )

    linhas_raw = contagens_raw[arquivo]
    linhas_bronze = spark.table(destino).count()

    if linhas_bronze != linhas_raw:
        raise RuntimeError(
            f"Contagem divergente para {tabela}: Raw={linhas_raw}, Bronze={linhas_bronze}."
        )

    return {
        "sistema": sistema,
        "tabela": tabela,
        "arquivo": arquivo,
        "linhas_raw": linhas_raw,
        "linhas_bronze": linhas_bronze,
        "status": "OK - contagem confere",
    }


resultados = [ingerir_tabela(sistema, tabela) for sistema, tabela in tabelas]
resultado_df = spark.createDataFrame(resultados).select(
    "sistema",
    "tabela",
    "arquivo",
    "linhas_raw",
    "linhas_bronze",
    "status",
)

print("Resumo da ingestão Bronze:")
resultado_df.show(10, truncate=False)

total_tabelas = len(resultados)
total_linhas = sum(resultado["linhas_bronze"] for resultado in resultados)

print(f"Quantidade de tabelas processadas: {total_tabelas}")
print(f"Total de linhas processadas: {total_linhas}")

