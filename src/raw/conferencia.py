# Databricks notebook source

from datetime import datetime, timezone
import re

from pyspark.sql.types import LongType, StringType, StructField, StructType, TimestampType


dbutils.widgets.text("catalog", "lakehouse_rotaperfume", "Catálogo")
catalog = dbutils.widgets.get("catalog").strip()

if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", catalog):
    raise ValueError(f"Nome de catálogo inválido: {catalog!r}")

arquivos_esperados = {
    "ERP": (
        "produtos.csv",
        "pedidos.csv",
        "itens_pedido.csv",
        "pagamentos.csv",
        "estoque.csv",
    ),
    "CRM": (
        "clientes.csv",
        "vendedores.csv",
        "carteira.csv",
        "oportunidades.csv",
        "visitas.csv",
    ),
}

caminhos = {
    "ERP": f"/Volumes/{catalog}/bronze/raw/erp/",
    "CRM": f"/Volumes/{catalog}/bronze/raw/crm/",
}

registros = []
erros = []
conferido_em = datetime.now(timezone.utc).replace(tzinfo=None)

for sistema, nomes in arquivos_esperados.items():
    diretorio = caminhos[sistema]

    try:
        arquivos_no_volume = {item.name.rstrip("/"): item for item in dbutils.fs.ls(diretorio)}
    except Exception as exc:
        erros.append(f"{sistema}: diretório ausente ou inacessível ({diretorio}): {exc}")
        continue

    for nome in nomes:
        caminho = f"{diretorio}{nome}"
        info = arquivos_no_volume.get(nome)

        if info is None:
            erros.append(f"{sistema}: arquivo ausente: {caminho}")
            continue

        if info.size <= 0:
            erros.append(f"{sistema}: arquivo vazio: {caminho}")
            continue

        try:
            linhas = (
                spark.read.option("header", "true")
                .option("multiLine", "true")
                .option("escape", '"')
                .csv(caminho)
                .count()
            )
        except Exception as exc:
            erros.append(f"{sistema}: arquivo inacessível ou CSV inválido ({caminho}): {exc}")
            continue

        if linhas <= 0:
            erros.append(f"{sistema}: arquivo sem linhas de dados: {caminho}")
            continue

        registros.append((sistema, nome, int(info.size), int(linhas), conferido_em))

if erros:
    raise RuntimeError("Falha na conferência Raw:\n- " + "\n- ".join(erros))

if len(registros) != 10:
    raise RuntimeError(f"Conferência incompleta: esperados 10 arquivos, encontrados {len(registros)}.")

schema = StructType(
    [
        StructField("sistema", StringType(), nullable=False),
        StructField("arquivo", StringType(), nullable=False),
        StructField("bytes", LongType(), nullable=False),
        StructField("linhas", LongType(), nullable=False),
        StructField("conferido_em", TimestampType(), nullable=False),
    ]
)

resultado_df = spark.createDataFrame(registros, schema=schema)
tabela = f"`{catalog}`.`bronze`.`_raw_arquivos`"

(
    resultado_df.write.mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(tabela)
)

spark.sql(
    f"COMMENT ON TABLE {tabela} IS "
    "'Conferência dos arquivos Raw recebidos antes da ingestão Bronze.'"
)

print("Conferência dos arquivos Raw concluída:")
resultado_df.orderBy("sistema", "arquivo").show(10, truncate=False)

resumo = resultado_df.agg(
    {"arquivo": "count", "linhas": "sum", "bytes": "sum"}
).first()
maior = resultado_df.orderBy(resultado_df.bytes.desc()).first()

print(f"Arquivos conferidos: {resumo['count(arquivo)']}")
print(f"Total de linhas de dados: {resumo['sum(linhas)']}")
print(f"Tamanho total em bytes: {resumo['sum(bytes)']}")
print(f"Maior arquivo: {maior['arquivo']} ({maior['linhas']} linhas)")

