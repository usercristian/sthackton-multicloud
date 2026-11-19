# SolidaryTech

SolidaryTech é um projeto acadêmico de uma plataforma sem fins lucrativos que conecta ONGs, doadores e voluntários. Este repositório contém três microsserviços de aplicação, seus Dockerfiles e workflows de CI/DevSecOps.

**Status:** os serviços e o pipeline de validação estão no repositório. A arquitetura multicloud, a infraestrutura e a operação descritas como objetivos ainda não estão provisionadas ou configuradas aqui.

## Serviços

| Serviço | Tecnologia | Porta padrão | Endpoints | Persistência |
|---|---|---:|---|---|
| `ngo-service` | Python / Flask | `8081` | `GET /health`, `GET /ngos`, `POST /ngos` | PostgreSQL |
| `donation-service` | Go / `net/http` | `8082` | `GET /health`, `GET /donations`, `POST /donations` | PostgreSQL; publicação opcional no AWS SQS |
| `volunteer-service` | Python / Flask | `8083` | `GET /health`, `POST /volunteers`, `GET /volunteers/<ngo_id>` | AWS DynamoDB |

O `donation-service` marca as doações como `APPROVED` por meio de uma simulação de gateway de pagamento. O SQS só é ativado quando `AWS_SQS_URL` e `AWS_REGION` estão configuradas. O endpoint de voluntários consulta a tabela DynamoDB usando uma operação `Scan`.

Os endpoints `/health` retornam o estado básico do processo; não substituem verificações de prontidão das dependências.

## Configuração

Os serviços leem variáveis do ambiente e também tentam carregar um arquivo `.env` local. Não há `.env.example` no repositório; configure os valores necessários antes de iniciar cada serviço.

| Variável | Serviço | Uso |
|---|---|---|
| `DATABASE_URL` | `ngo-service`, `donation-service` | Obrigatória; URL de conexão com PostgreSQL |
| `AWS_DYNAMODB_TABLE` | `volunteer-service` | Obrigatória; nome da tabela DynamoDB |
| `AWS_REGION` | `volunteer-service` | Região AWS; o código usa `us-east-1` se não informada |
| `AWS_SQS_URL` | `donation-service` | URL da fila SQS; junto com `AWS_REGION`, habilita a integração |
| `AWS_REGION` | `donation-service` | Obrigatória para habilitar a integração com SQS |
| `PORT` | Todos | Porta HTTP; cada serviço usa a porta padrão indicada acima |

Os serviços que acessam AWS também precisam de credenciais configuradas pelo mecanismo padrão do AWS SDK. Não armazene credenciais no repositório.

Os scripts [`ngo-service/db/init.sql`](./ngo-service/db/init.sql) e [`donation-service/db/init.sql`](./donation-service/db/init.sql) criam as respectivas tabelas PostgreSQL. O primeiro também insere dois registros de exemplo. Execute cada script uma vez contra o banco usado pelo serviço correspondente. A criação da tabela DynamoDB não está automatizada neste repositório.

## Execução local

Não há Docker Compose ou automação local para provisionar PostgreSQL/DynamoDB. Disponibilize as dependências, configure as variáveis e execute cada serviço em um terminal separado.

### `ngo-service`

Requer Python 3.11 e PostgreSQL com o schema inicial aplicado.

```bash
cd ngo-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL="postgresql://usuario:senha@localhost:5432/ngos"
python app.py
```

### `donation-service`

Requer Go 1.25.7 e PostgreSQL com o schema inicial aplicado. Para executar sem integração SQS, basta configurar `DATABASE_URL`.

```bash
cd donation-service
export DATABASE_URL="postgresql://usuario:senha@localhost:5432/donations"
go run .
```

Para habilitar o SQS, configure também `AWS_SQS_URL`, `AWS_REGION` e as credenciais AWS.

### `volunteer-service`

Requer Python 3.11, uma tabela DynamoDB existente e credenciais AWS.

```bash
cd volunteer-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export AWS_DYNAMODB_TABLE="nome-da-tabela"
export AWS_REGION="us-east-1"
python app.py
```

## Containers e CI

Há um Dockerfile em cada diretório de serviço. O workflow [`ci-apps.yml`](./.github/workflows/ci-apps.yml) é acionado por alterações nos serviços/workflows em `master`, por pull requests para `master` ou manualmente (`workflow_dispatch`). Ele identifica quais serviços precisam ser processados e chama o workflow reutilizável [`_reusable-ci-devsecops.yml`](./.github/workflows/_reusable-ci-devsecops.yml).

O pipeline configura:

- Go: `go build`, `go test`, `go vet` e `golangci-lint`.
- Python: compilação de sintaxe e `pytest` (a ausência de testes é aceita), além de verificações selecionadas do Flake8.
- Segurança: gosec para Go, Bandit para Python e Trivy para vulnerabilidades/secrets em arquivos e imagens, bloqueando achados CRITICAL.
- Container: build da imagem para `linux/arm64` e scan com Trivy.

O build de container não publica imagens nem realiza deploy. Não há workflows de Terraform, Kubernetes ou GitOps neste repositório. Atualmente não há arquivos de teste dos serviços; o pipeline executa os comandos de teste, mas isso não significa que existam testes funcionais implementados.

## Estado do projeto

### Presente no repositório

- Código dos três serviços e endpoints básicos de saúde e operação.
- Dockerfiles e arquivos de dependências.
- Scripts SQL iniciais para os bancos PostgreSQL dos serviços de ONGs e doações.
- Workflows de CI, análise estática, scans de segurança e build/scan de imagens.
- Regras de governança de engenharia em [`AGENTS.md`](./AGENTS.md).

### Planejado, ainda não implementado aqui

A arquitetura-alvo descrita em `AGENTS.md` prevê OCI como provedor principal e AWS para mensageria, NoSQL e recuperação de desastres. Porém, este repositório ainda não contém a infraestrutura ou os recursos operacionais para materializar essa arquitetura. Permanecem pendentes:

- Módulos Terraform, ambientes OCI/AWS e backends de estado.
- Recursos AWS (SQS/DLQ e DynamoDB) provisionados por IaC.
- Cluster Kubernetes, manifestos de aplicação e entrega via ArgoCD.
- Workflows de provisionamento/destruição de infraestrutura.
- Docker Compose e configuração de ambiente de desenvolvimento reproduzível.
- Testes automatizados dos serviços.
- Dashboards, SLIs/SLOs, APM/AIOps e validação de Disaster Recovery.
