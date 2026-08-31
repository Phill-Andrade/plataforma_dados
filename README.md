# Plataforma de Dados

Plataforma local de Hadoop, YARN, Spark e Hive Metastore para equipes que precisam executar pipelines externos sobre uma infraestrutura de dados reproduzível com Docker Compose.

---

## Index

- [Quickstart](#quickstart)
- [Usage](#usage)
- [Arquitetura](#arquitetura)
- [Configuração](#configuração)
- [Integração com clientes externos](#integração-com-clientes-externos)
- [Testes](#testes)
- [Project Structure](#project-structure)
- [Escopo e segurança](#escopo-e-segurança)
- [Contribution Guidelines](#contribution-guidelines)
- [Versioning and Releases](#versioning-and-releases)
- [Personas and Responsibilities](#personas-and-responsibilities)

---

## Quickstart

### Pré-requisitos

- Docker Engine;
- Docker Compose v2 (`docker compose`);
- Bash;
- `curl` para a verificação HTTP opcional;
- acesso à internet no primeiro build para baixar Hadoop, Spark, Hive e o driver PostgreSQL.

As versões, os checksums e o digest da imagem-base ficam fixados no Dockerfile. A topologia local usa valores literais nos arquivos que são responsáveis por cada configuração.

### Inicialização

Na raiz do repositório:

```bash
./scripts/start-platform.sh
```

O Compose constrói a imagem compartilhada definida na âncora `x-hadoop-service` e mantém os containers em primeiro plano. Por padrão, são iniciados dois DataNodes e dois NodeManagers, cada daemon em seu próprio container. Builds posteriores reutilizam o cache do Docker quando os arquivos da imagem não mudam.

Para encerrar os containers:

```bash
./scripts/start-platform.sh --down
```

Os volumes nomeados do NameNode e do PostgreSQL são preservados. O comando não usa `--volumes`.

### Verificação mínima

Com a plataforma ativa, em outro terminal:

```bash
curl --fail http://localhost:9870/ >/dev/null
curl --fail http://localhost:8088/ >/dev/null
curl --fail http://localhost:18080/ >/dev/null
```

Essas URLs correspondem às interfaces do HDFS NameNode, YARN ResourceManager e Spark History Server.

### Running Tests

Testes rápidos, sem exigir containers ativos:

```bash
for test in tests/shell/test_*.sh; do
  bash "$test"
done
```

Teste real do Hive, com a plataforma ativa:

```bash
bash tests/integration/test_hive_metastore.sh
```

O teste de integração valida o schema do Metastore e cria, consulta e remove uma tabela técnica temporária.

---

## Usage

### Ciclo de vida da plataforma

Iniciar a stack:

```bash
./scripts/start-platform.sh
```

Escalar os DataNodes e NodeManagers de uma stack em execução:

```bash
./scripts/start-platform.sh --workers 4
```

O script aplica a mesma quantidade aos serviços `datanode` e `nodemanager`. O valor deve estar entre 1 e 12, de acordo com os ranges de portas publicados.

Encerrar a stack:

```bash
./scripts/start-platform.sh --down
```

### Cliente Spark de diagnóstico

O serviço `spark-client` existe apenas para diagnóstico e execução manual. Ele não contém nem monta código de pipeline.

```bash
docker compose \
  -f infrastructure/compose/compose.yaml \
  --profile tools \
  run --rm --no-deps spark-client
```

A stack deve estar ativa. A opção `--no-deps` impede que o Compose tente recriar os serviços distribuídos ao abrir apenas o cliente de diagnóstico.

Dentro do container, use `/opt/spark/bin/spark-submit`; os comandos `hdfs` e `yarn` estão disponíveis no `PATH`. O código submetido deve ser fornecido externamente pelo usuário ou pelo orquestrador.

### Casos de uso suportados

- **Armazenamento distribuído**
  - Entrada: arquivos enviados por clientes Hadoop conectados à rede da plataforma.
  - Saída: dados persistidos no HDFS.
- **Processamento Spark sobre YARN**
  - Entrada: aplicação Spark externa e suas dependências.
  - Saída: aplicação registrada no YARN e eventos disponíveis no Spark History Server quando emitidos pelo job.
- **Catálogo técnico**
  - Entrada: definições de databases e tabelas enviadas ao Hive Metastore.
  - Saída: metadados persistidos no PostgreSQL.

A plataforma não contém regras de negócio, nomes de tabelas de pipelines, DAGs ou código de transformação.

---

## Arquitetura

| Componente | Responsabilidade | Endpoint interno | Acesso pelo host |
|---|---|---|---|
| HDFS NameNode | Namespace e coordenação do armazenamento | `namenode:9000` | UI em `http://localhost:9870` |
| HDFS DataNode | Armazenamento de blocos | portas internas do Hadoop | UIs no range `19864-19875` |
| YARN ResourceManager | Agendamento e acompanhamento de aplicações | `resourcemanager:8032` | UI em `http://localhost:8088` |
| YARN NodeManager | Execução nos workers | portas internas do YARN | UIs no range `8042-8053` |
| Hive Metastore | Catálogo Thrift | `hive-metastore:9083` | `localhost:9083` |
| PostgreSQL | Persistência do schema do Metastore | `postgres:5432` | `localhost:5432` |
| Spark History Server | Histórico de aplicações Spark | `spark-history:18080` | `http://localhost:18080` |
| Spark client | Diagnóstico e submissão manual | rede da plataforma | perfil Compose `tools` |

O Hive Metastore não é um HiveServer2. A porta `9083` oferece o catálogo Thrift; ela não é um endpoint JDBC/SQL para consultas de dados.

O volume do NameNode e o volume do PostgreSQL são persistentes. Cada réplica de `datanode` utiliza um volume anônimo próprio para seus blocos.

---

## Configuração

A topologia do HDFS é definida diretamente em `hdfs-site.xml`, enquanto os limites da escala local pertencem ao script `scale-workers.sh`. O Compose não injeta um arquivo de ambiente compartilhado nos containers.

Exemplo:

```bash
POSTGRES_PASSWORD='defina-um-segredo-local' \
  ./scripts/start-platform.sh
```

Não versione senhas reais.

### Versões

As versões e os checksums da imagem são definidos como `ARG` no [`Dockerfile`](infrastructure/docker/base/Dockerfile). Eles ainda podem ser sobrescritos com `--build-arg` em builds manuais.

| Variável | Uso |
|---|---|
| `HADOOP_VERSION` | Distribuição Hadoop instalada na imagem. |
| `HIVE_VERSION` | Distribuição Hive instalada na imagem. A compatibilidade do Spark está fixada em `3.1.3` no `spark-defaults.conf`. |
| `SPARK_VERSION` | Distribuição Spark instalada na imagem. |
| `JAR_POSTGRES_VERSION` | Driver JDBC copiado para o Hive. |
| `HADOOP_SHA512` | Integridade do pacote Hadoop. |
| `SPARK_SHA512` | Integridade do pacote Spark. |
| `HIVE_SHA256` | Integridade do pacote Hive. |
| `JAR_POSTGRES_SHA256` | Integridade do driver PostgreSQL. |

O build rejeita qualquer download cujo conteúdo não corresponda ao checksum versionado.

### Topologia e HDFS

O `hdfs-site.xml` define fator de replicação 2 e exige dois DataNodes ativos antes de o NameNode sair do safe mode. O Compose inicia duas réplicas de `datanode` e duas de `nodemanager`.

### Portas dos workers

O Compose publica os ranges fixos `8042-8053` para as UIs do NodeManager e `19864-19875` para as UIs do DataNode. Cada range comporta até 12 workers, limite também aplicado pelo script de escala.

### Inicialização HDFS

O healthcheck do NameNode aguarda a saída do safe mode. Depois disso, o serviço descartável `hdfs-init` cria os diretórios técnicos e publica no HDFS o archive versionado das bibliotecas do Spark quando ele ainda não existe. Os daemons Hadoop e YARN permanecem como processos principais de seus containers.

### Logs de aplicações

O YARN agrega em `/yarn_logs` no HDFS os logs produzidos pelos containers das aplicações e os conserva por sete dias. Eles podem ser consultados com `yarn logs -applicationId APPLICATION_ID`. O Spark History Server usa separadamente `/spark_events` para reconstruir jobs, stages e tasks.

O `spark-defaults.conf` centraliza execução sobre YARN, event logs, warehouse e integração com o Hive. Endpoints já definidos nos XMLs do Hadoop e portas que usam defaults nativos do Spark não são repetidos nesse arquivo.

O `spark.yarn.archive` aponta para `/spark/spark-libs-3.5.5.zip` no HDFS. O YARN reutiliza esse archive em vez de receber todas as bibliotecas instaladas em `$SPARK_HOME/jars` a cada submissão.

### Banco do Metastore

`POSTGRES_PASSWORD` configura a senha compartilhada pelo PostgreSQL e pelo Hive Metastore. O fallback presente no Compose destina-se somente ao desenvolvimento local; defina a variável explicitamente em qualquer ambiente compartilhado.

---

## Integração com clientes externos

A stack cria a rede Docker `data-platform-network` com nome estável. Um container de outro projeto pode ingressar nessa rede enquanto ela existir.

Em outro arquivo Compose:

```yaml
services:
  external-client:
    image: sua-imagem
    networks:
      - data_platform_network

networks:
  data_platform_network:
    external: true
    name: data-platform-network
```

O cliente deve usar os seguintes nomes DNS e protocolos:

| Serviço | Configuração do cliente |
|---|---|
| HDFS | `fs.defaultFS=hdfs://namenode:9000` |
| YARN | `yarn.resourcemanager.hostname=resourcemanager` |
| Hive Metastore | `hive.metastore.uris=thrift://hive-metastore:9083` |

Contrato de integração:

1. o cliente fornece seu próprio código e dependências;
2. a plataforma fornece HDFS, YARN, Spark e o catálogo Hive;
3. o cliente ingressa em `data-platform-network` e usa os aliases estáveis;
4. nenhuma DAG, tabela de domínio ou regra de pipeline é adicionada a este repositório;
5. credenciais e configurações específicas do pipeline permanecem no projeto consumidor.

As portas RPC do HDFS e do YARN não são publicadas diretamente no host. Clientes Hadoop completos devem executar em containers conectados à rede da plataforma. As portas HTTP publicadas no host servem para observabilidade.

---

## Testes

### Testes shell rápidos

- [`tests/shell/test_hive_bootstrap.sh`](tests/shell/test_hive_bootstrap.sh): classificação e inicialização do schema Hive com comandos simulados.
- [`tests/shell/test_namenode_init.sh`](tests/shell/test_namenode_init.sh): formatação idempotente do volume do NameNode;
- [`tests/shell/test_platform_configuration.sh`](tests/shell/test_platform_configuration.sh): contratos do Compose, XMLs, Spark e Dockerfile;
- [`tests/shell/test_scale_workers.sh`](tests/shell/test_scale_workers.sh): validação e escala conjunta dos workers;
- [`tests/shell/test_start_platform.sh`](tests/shell/test_start_platform.sh): ciclo de vida e delegação do comando público.

O workflow [`.github/workflows/validate.yml`](.github/workflows/validate.yml) executa a validação de sintaxe e esses testes em pull requests e pushes para `dev`, `main` e `master`.

### Teste Hive real

[`tests/integration/test_hive_metastore.sh`](tests/integration/test_hive_metastore.sh) exige a stack ativa e verifica:

- estado saudável do container Hive Metastore;
- validade do schema persistido no PostgreSQL;
- criação de database e tabela temporários;
- retorno da tabela por `SHOW TABLES`;
- retorno das colunas por `DESCRIBE`;
- limpeza automática do database temporário.

Os testes de resolução DNS externa e de pipeline Spark ponta a ponta não fazem parte desta fase.

---

## Project Structure

```text
.
├── .github/workflows/validate.yml       # Validação contínua de scripts e configurações
├── infrastructure/
│   ├── compose/
│   │   └── compose.yaml                 # Serviços, rede, volumes e healthchecks
│   ├── configs/
│   │   ├── hadoop/core-site.xml         # Endpoint padrão do HDFS
│   │   ├── hdfs/hdfs-site.xml           # Replicação e diretórios do HDFS
│   │   ├── hive/hive-site.xml           # PostgreSQL e endpoint do Metastore
│   │   ├── spark/spark-defaults.conf    # Spark sobre YARN, eventos e catálogo
│   │   └── yarn/yarn-site.xml           # ResourceManager e NodeManagers
│   ├── docker/base/Dockerfile           # Imagem comum da plataforma
│   └── entrypoints/
│       ├── hive-metastore/entrypoint.sh  # Bootstrap e processo do Metastore
│       ├── hdfs-init/entrypoint.sh        # Diretórios técnicos e archive do Spark
│       └── namenode-init/entrypoint.sh   # Formatação idempotente do NameNode
├── scripts/
│   ├── scale-workers.sh                  # Escala validada dos workers
│   └── start-platform.sh                 # Ciclo de vida público da stack
├── tests/
│   ├── integration/
│   │   └── test_hive_metastore.sh        # Smoke test contra serviços reais
│   └── shell/                            # Testes rápidos e de consistência
│       ├── helpers/
│       │   ├── assertions.sh             # Resultado agregado das suítes
│       │   ├── command_assertions.sh     # Assertions reutilizáveis para comandos
│       │   └── temporary_directories.sh  # Diretórios temporários com cleanup defensivo
│       ├── test_hive_bootstrap.sh        # Bootstrap do schema e processo Hive
│       ├── test_namenode_init.sh         # Formatação idempotente do NameNode
│       ├── test_platform_configuration.sh # Contratos estáticos da plataforma
│       ├── test_scale_workers.sh         # Escala dos DataNodes e NodeManagers
│       └── test_start_platform.sh        # Ciclo de vida público
└── README.md
```

---

## Escopo e segurança

Esta configuração atende desenvolvimento e integração local. O Hadoop está em modo `simple`, portanto não oferece autenticação forte.

Ficam explicitamente fora do escopo atual:

- Kerberos e Hadoop Secure Mode;
- TLS entre os serviços;
- autorização Hadoop completa;
- configuração de produção e alta disponibilidade;
- Kubernetes;
- Livy;
- API própria de submissão;
- múltiplos pipelines administrados pela plataforma;
- DAGs do Airflow e código de pipelines.

Kerberos, TLS e autorização devem ser tratados antes de uma implantação de produção.

---

## Contribution Guidelines

### Pull Request Workflow

1. Trabalhe em uma branch dedicada a uma alteração coesa.
2. Mantenha neste repositório somente infraestrutura e contratos genéricos.
3. Execute os testes shell e, quando houver alteração no Hive, o teste de integração.
4. Atualize o README quando comandos, estrutura, endpoints ou variáveis mudarem.

### Code Quality Standards

- Scripts Bash devem usar modo estrito quando aplicável e passar por `bash -n`.
- O Compose deve passar por:

  ```bash
  docker compose \
    -f infrastructure/compose/compose.yaml \
    config --quiet
  ```

- Defaults duplicados devem possuir fonte única ou teste explícito de consistência.
- Testes de integração devem criar recursos técnicos temporários e removê-los automaticamente.
- Não há política de cobertura numérica definida para os testes shell.

---

## Versioning and Releases

As versões dos runtimes ficam no [`Dockerfile`](infrastructure/docker/base/Dockerfile). O repositório ainda não possui tags, changelog ou automação de releases observáveis.

<!-- TODO: definir estratégia de versionamento, política de breaking changes e mecanismo de release. -->

---

## Personas and Responsibilities

### Mantenedores da plataforma

- mantêm Compose, imagens, configurações, entrypoints e testes de infraestrutura;
- preservam aliases, endpoints e contratos de integração compatíveis;
- não adicionam regras específicas de pipelines.

### Equipes consumidoras de pipelines

- mantêm DAGs, aplicações Spark, dependências e regras de negócio em repositórios próprios;
- conectam seus containers à `data-platform-network`;
- submetem jobs usando os endpoints documentados;
- não dependem de código de pipeline armazenado nesta plataforma.
