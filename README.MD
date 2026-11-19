# Ecossistema Cloud-Native, SRE, FinOps e Disaster Recovery

## 1. Visão Geral e Contexto Acadêmico

SolidaryTech é uma plataforma sem fins lucrativos que conecta ONGs a doadores e voluntários em todo o Brasil. Este repositório reúne a implementação do Tech Challenge (Hackathon Fase 5 — POS TECH), cujo objetivo é comprovar maturidade operacional, financeira e de resiliência em nuvem aplicando práticas de DevOps, SRE, FinOps, Segurança, ITSM/AIOps e Disaster Recovery.

Diretriz central: toda a infraestrutura e entrega de software seguem automação declarativa (IaC e GitOps), sem provisionamento manual em console ou deploys manuais via `kubectl`.

## 2. Componentes da Aplicação

O ecossistema é composto por três microsserviços independentes:

- `ngo-service` (Python / Flask — Porta `8081`): cadastro e listagem de ONGs parceiras. Persiste dados no PostgreSQL (`DATABASE_URL`).
- `donation-service` (Go — Porta `8082`): processamento síncrono de doações (caminho crítico / hot path) no PostgreSQL (`DATABASE_URL`) e publicação assíncrona de eventos de notificação no AWS SQS (`AWS_SQS_URL`).
- `volunteer-service` (Python / Flask — Porta `8083`): registro e consulta de voluntários por ONG, persistindo dados no AWS DynamoDB (`AWS_DYNAMODB_TABLE`).

Todos os serviços expõem o endpoint `/health` para verificação de integridade (liveness/readiness probes).

## 3. Arquitetura e Estratégia Multicloud

Para equilibrar os requisitos técnicos do desafio com a preservação do código-fonte original das aplicações e a otimização de custos (FinOps), o projeto adota uma arquitetura híbrida OCI + AWS com Disaster Recovery em Warm Standby:

- Provedor Principal — Oracle Cloud Infrastructure (OCI / `sa-saopaulo-1`):
  - Rede: VCN isolada com sub-redes pública (Load Balancer), privada de aplicação (OKE) e privada de dados (PostgreSQL).
  - Orquestração: Oracle Container Engine for Kubernetes (OKE) com Worker Nodes ARM64 (`VM.Standard.A1.Flex`).
  - Banco Relacional: OCI Database with PostgreSQL hospedando os bancos lógicos dos serviços de ONGs e doações.
  - Ciclo de Vida Efêmero (FinOps): provisionamento sob demanda (`terraform apply`) e destruição em períodos ociosos (`terraform destroy`) via workflows no GitHub Actions.
- Provedor Secundário & DR — Amazon Web Services (AWS):
  - Mensageria e NoSQL: Amazon SQS (com Dead Letter Queue) e Amazon DynamoDB ativos para integração nativa com os SDKs originais dos microsserviços.
  - Disaster Recovery (Warm Standby): módulos Terraform isolados (`VPC`, `EKS`, `RDS`) habilitados sob demanda (`enable_warm_standby = true`) para recuperação rápida em caso de indisponibilidade do ambiente principal na OCI.
- Observabilidade, GitOps e Segurança:
  - Entrega Contínua: GitHub Actions (testes, scan de vulnerabilidades com Trivy, build multi-arch `linux/arm64`) + ArgoCD no cluster.
  - Monitoramento e AIOps: Prometheus e Grafana (SLIs/SLOs e Error Budget para o `donation-service`) + Datadog APM com Distributed Tracing e Watchdog (detecção preditiva de anomalias).
  - Governança FinOps: políticas obrigatórias de tags via Terraform (`Project=Solidary Tech`, `Environment=Production`, `CostCenter=NGO-Core`) e rightsizing de `requests`/`limits` nos manifestos Kubernetes.

## 4. Organização Planejada do Repositório

```text
.
├── AGENTS.md                        # Regras de governança de engenharia
├── README.md                        # Documentação central do projeto
├── donation-service/                # Código-fonte Go e Dockerfile
├── ngo-service/                     # Código-fonte Python e Dockerfile
├── volunteer-service/               # Código-fonte Python e Dockerfile
├── infra/                           # Infraestrutura como Código (Terraform)
│   ├── bootstrap/                   # Buckets persistentes para remote state
│   │   ├── oci-state/
│   │   └── aws-state/
│   ├── modules/                     # Módulos reutilizáveis isolados por nuvem
│   │   ├── oci/                     # network, oke, postgres
│   │   └── aws/                     # messaging-nosql, network, eks, rds
│   └── environments/                # Composições de ambiente
│       ├── oci-prod/                # Ambiente principal OCI
│       └── aws-dr/                  # Ambiente AWS (SQS/DynamoDB + DR Warm Standby)
├── k8s/                             # Manifestos GitOps gerenciados pelo ArgoCD
│   ├── apps/                        # Deployments, Services, Ingress e Secrets templates
│   └── observability/               # Configurações Prometheus, Grafana e Datadog
└── .github/
    └── workflows/                   # Pipelines CI/CD, DevSecOps e Infra Apply/Destroy

```

## 5. Status Atual da Implementação

* [x] Código-fonte base dos microsserviços (`ngo-service`, `donation-service`, `volunteer-service`) inspecionado.
* [x] Arquitetura híbrida OCI + AWS (ACP-001 Rev. 2) definida e aprovada.
* [x] Governança (`AGENTS.md`) e documentação central (`README.md`) estruturadas.
* [ ] Containerização otimizada (`linux/arm64`) e validação local.
* [ ] Módulos Terraform (Bootstrap, OCI Prod e AWS DR) com tagging FinOps.
* [ ] Pipelines GitHub Actions (DevSecOps e ciclo efêmero `apply`/`destroy`).
* [ ] Manifestos Kubernetes com rightsizing e deploy via ArgoCD.
* [ ] Dashboards SRE (Grafana), APM/AIOps (Datadog) e validação de DR.

## 6. Execução Local (Em Desenvolvimento)

As instruções de execução via Docker Compose e variáveis de ambiente (`.env.example`) serão adicionadas na próxima etapa após a criação dos Dockerfiles de cada microsserviço.

