# sthackton-multicloud — Ecossistema Cloud-Native, SRE, FinOps e Disaster Recovery

## 1. Visão Geral e Contexto Acadêmico

SolidaryTech é uma plataforma sem fins lucrativos que conecta ONGs a doadores e voluntários em todo o Brasil. Este repositório reúne a implementação do Tech Challenge (Hackathon Fase 5 — POS TECH), cujo objetivo é comprovar maturidade operacional, financeira e de resiliência em nuvem aplicando práticas de DevOps, SRE, FinOps, Segurança, ITSM/AIOps e Disaster Recovery.

Diretriz central: toda a infraestrutura e entrega de software seguem automação declarativa (IaC e GitOps), sem provisionamento manual em console ou deploys manuais via `kubectl`.

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

Os scripts [`services/ngo-service/db/init.sql`](./services/ngo-service/db/init.sql) e [`services/donation-service/db/init.sql`](./services/donation-service/db/init.sql) criam as respectivas tabelas PostgreSQL. O primeiro também insere dois registros de exemplo. Execute cada script uma vez contra o banco usado pelo serviço correspondente. A criação da tabela DynamoDB não está automatizada neste repositório.

## Execução local

Não há Docker Compose ou automação local para provisionar PostgreSQL/DynamoDB. Disponibilize as dependências, configure as variáveis e execute cada serviço em um terminal separado.

### `ngo-service`

Requer Python 3.11 e PostgreSQL com o schema inicial aplicado.

```bash
cd services/ngo-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL="postgresql://usuario:senha@localhost:5432/ngos"
python app.py
```

### `donation-service`

Requer Go 1.25.7 e PostgreSQL com o schema inicial aplicado. Para executar sem integração SQS, basta configurar `DATABASE_URL`.

```bash
cd services/donation-service
export DATABASE_URL="postgresql://usuario:senha@localhost:5432/donations"
go run .
```

Para habilitar o SQS, configure também `AWS_SQS_URL`, `AWS_REGION` e as credenciais AWS.

### `volunteer-service`

Requer Python 3.11, uma tabela DynamoDB existente e credenciais AWS.

```bash
cd services/volunteer-service
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
- Container: build da imagem para `linux/arm64` e scan com Trivy. Em `push` para `master` e em `workflow_dispatch`, publica no OCIR a tag canônica do SHA completo e também `latest`; pull requests apenas constroem e analisam as imagens.

O workflow de publicação usa as credenciais OCI configuradas como secrets do GitHub Actions (`OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY` e `OCI_COMPARTMENT_OCID`). O Vault e o Auth Token `solidarytech-ocir-token` são provisionados pelo preflight do workflow de infraestrutura, não pelo CI de aplicações. Durante a publicação, o runner lê o token do Vault somente para o login via `--password-stdin`; o CI não acessa OKE/Kubernetes, não instala charts e não provisiona infraestrutura. Pull requests apenas constroem e analisam as imagens.

Em `push` para `master` e em `workflow_dispatch`, o job `update-gitops-manifests` roda após os builds/publicações, atualiza somente os serviços bem-sucedidos em `k8s/overlays/oci-prod/kustomization.yaml` com o SHA completo e faz `git pull --rebase origin master` antes do commit/push. O commit usa a mensagem `chore(gitops): update image tags to <sha-curto> [skip ci]`; ArgoCD observa a mudança no Git e reconcilia os Deployments com imagens rastreáveis pelo commit. Atualmente não há arquivos de teste dos serviços; o pipeline executa os comandos de teste, mas isso não significa que existam testes funcionais implementados.

## Kubernetes e Kustomize

Os recursos estão organizados em `k8s/base/` (Namespace, Deployments e Services `ClusterIP`) e `k8s/overlays/oci-prod/` (ConfigMap, Job de inicialização PostgreSQL, Ingress e configuração das imagens OCIR). Todas as referências de imagem são qualificadas com registry: o Job usa `docker.io/library/postgres:15-alpine` e os serviços usam `gru.ocir.io/grqecn36frj4/solidarytech/`; o overlay fixa as tags publicadas. Os Deployments usam probes HTTP em `/health`, `imagePullPolicy: IfNotPresent`, limites enxutos para workers ARM64 e `revisionHistoryLimit: 0` para remover ReplicaSets inativos após atualizações; o rollback de versões deve ser feito a partir do Git. O Job conecta primeiro ao database administrativo `postgres`, cria `ngos` e `donations` de forma idempotente e então aplica os scripts SQL versionados em `services/` nos respectivos bancos. As definições de tabela usam `IF NOT EXISTS` e o seed de ONGs usa `ON CONFLICT DO NOTHING`, permitindo reaplicações.

A Application [`k8s/argocd/solidarytech-oci-prod.yaml`](./k8s/argocd/solidarytech-oci-prod.yaml) aponta para o overlay de produção e habilita sincronização automática, pruning e self-heal. O workflow manual [`gitops-oke-bootstrap.yml`](./.github/workflows/gitops-oke-bootstrap.yml) inicializa o backend remoto apenas para ler os outputs `oke_cluster_id`, `postgres_private_ip` e `postgres_admin_username`; se o OKE não estiver provisionado, orienta executar primeiro `infra-oci-lifecycle.yml` com `apply`. O script [`infra/scripts/oci-oke-gitops-bootstrap.sh`](./infra/scripts/oci-oke-gitops-bootstrap.sh) recebe esses valores, valida o cluster pelo ID e estado `ACTIVE`, verifica `/readyz` e aguarda nós ARM64 `Ready` antes de instalar/atualizar ArgoCD e Traefik via Helm e aplicar a Application. Ele lê os secrets `solidarytech-ocir-token` e `solidarytech-postgres-password` do OCI Vault e cria/atualiza, de forma idempotente, no namespace `solidarytech`:

- `ocir-secret`, do tipo `kubernetes.io/dockerconfigjson`, para pull das imagens privadas no OCIR.
- `solidarytech-db-secret`, com `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `NGO_DATABASE_URL` e `DONATION_DATABASE_URL`.

O Secret de pull usa o mesmo registry `gru.ocir.io` das imagens, é associado à ServiceAccount `default` e está declarado nos três Deployments. O Auth Token é lido do Vault durante o bootstrap; seus valores não são armazenados nos manifests ou impressos nos logs. A atualização dos Secrets ocorre em cada execução do bootstrap; não há ainda um controlador de rotação contínua independente do pipeline. O Ingress usa a classe `traefik`; o bootstrap instala o chart oficial `traefik/traefik` com uma réplica e requests de `100m`/`128Mi`, dimensionados para o nó ARM64. O painel ArgoCD é publicado diretamente pelo Traefik em `/argocd`, sem exigir port-forward. O preflight cria `solidarytech-argocd-admin-password` no OCI Vault somente quando ausente, preservando a senha entre execuções e ciclos de infraestrutura; o bootstrap mantém apenas o hash bcrypt no Secret Kubernetes e remove `argocd-initial-admin-secret`. O Job Summary do workflow fornece a URL, o comando OCI para recuperar a senha localmente e os comandos `curl` dos endpoints de saúde; senha e hash não são exibidos nos logs nem no sumário.

O ConfigMap define a tabela DynamoDB `solidarytech-volunteers` e a região `us-east-1`; a tabela deve existir na AWS e as credenciais AWS do `volunteer-service` precisam ser disponibilizadas por um mecanismo de identidade configurado fora destes manifests. O Ingress Traefik consolida o tráfego externo. Como os arquivos SQL do `configMapGenerator` ficam fora da pasta do overlay, a renderização local requer `kustomize build --load-restrictor LoadRestrictionsNone k8s/overlays/oci-prod`; execute essa opção apenas para este repositório confiável. A renderização não aplica recursos ao cluster.

## Infraestrutura como Código (IaC) e Automação OCI

A camada de infraestrutura na Oracle Cloud Infrastructure (`sa-saopaulo-1`) está organizada de forma modular em `infra/`:

Os três fluxos têm responsabilidades separadas: `infra-oci-lifecycle.yml` gerencia o ciclo Terraform, `gitops-oke-bootstrap.yml` lê o state e configura ArgoCD/Traefik/Secrets no OKE sob demanda, e `ci-apps.yml` valida/publica imagens e atualiza somente os manifests Git. O CI de aplicações não recebe credenciais Kubernetes nem permissões para acessar o cluster.

- `infra/scripts/oci-state-preflight.sh`: script idempotente executado antes do `terraform init` para validar ou criar o bucket privado e versionado de estado remoto (`solidarytech-tfstate-prod`) no Object Storage.
- `infra/scripts/oci-secrets-preflight.sh`: bootstrap idempotente e persistente do OCI Vault `solidarytech-vault-prod`, da Master Key AES-256/SOFTWARE, do segredo da senha do banco e do Auth Token do OCIR (`solidarytech-ocir-token`); esses recursos ficam fora do ciclo de `terraform destroy`.
- `infra/modules/oci/network/`: módulo de rede contendo VCN (`10.0.0.0/16`), Internet Gateway, NAT Gateway, Service Gateway, tabelas de roteamento, Security Lists (incluindo regras de registro de workers OKE em `TCP/6443`, `TCP/12250` e `ICMP 3/4`) e sub-redes isoladas (`public-lb`, `private-oke` e `private-db`).
- `infra/modules/oci/oke/`: módulo de computação contendo cluster OKE (`BASIC_CLUSTER`, Kubernetes `v1.36.4`) e Node Pool ARM64 (`VM.Standard.A2.Flex` com seleção dinâmica de imagem Oracle Linux 8.10 `aarch64` e restrição configurável de Fault Domain). A configuração retira os repositórios OCIR do gerenciamento Terraform; no próximo `apply`, o bloco `removed` os desassocia do state sem excluí-los da OCI, e os outputs preservam seus nomes para referência.
- `infra/modules/oci/postgres/`: módulo do OCI Database with PostgreSQL, com padrão `PostgreSQL.VM.Standard.E5.Flex` na sub-rede privada `10.0.3.0/24`, credencial `VAULT_SECRET` e acesso ao banco restrito à sub-rede do OKE (`10.0.2.0/24`) em `TCP/5432`.
- `infra/environments/oci-prod/`: composição do ambiente principal (`main.tf`, `iam.tf`, `variables.tf`, `outputs.tf`, `versions.tf`) utilizando o backend nativo `backend "oci"` (Terraform `1.12.0+`).
- `.github/workflows/infra-oci-lifecycle.yml` e `.github/workflows/_reusable-terraform.yml`: PRs em `infra/**` fazem validações read-only do backend/Vault e executam somente `plan`; `workflow_dispatch` permite `plan`, `apply` e `destroy`, com preflights idempotentes. O grupo de concorrência `oci-infra-lifecycle` serializa execuções. Antes do destroy, o workflow usa `oke_cluster_id` do Terraform State e, se o cluster estiver `ACTIVE`, libera temporariamente o IPv4 do runner em TCP/6443 na Security List `solidarytech-sl-public-lb`, remove regras temporárias órfãs e configura o kubeconfig com permissão `600`. Em seguida, remove o release Helm `traefik`; um `trap` de saída revoga as regras temporárias mesmo se a remoção falhar, antes que o job prossiga para o `terraform destroy`. `ingress-nginx` permanece apenas para compatibilidade.
- `infra/scripts/oci-oke-gitops-bootstrap.sh`: bootstrap idempotente de ArgoCD, Traefik, Secrets do namespace e Application GitOps no OKE.
- `.github/workflows/gitops-oke-bootstrap.yml`: workflow manual separado para obter os outputs do Terraform, validar prontidão do OKE e executar o bootstrap; antes do bootstrap, remove regras temporárias órfãs de execuções anteriores e libera o IPv4 efêmero do runner em TCP/6443 na Security List `solidarytech-sl-public-lb`, identificando a regra pela execução. O step `if: always()` revoga a regra atual e qualquer regra temporária remanescente. Com a allow-list administrativa Terraform vazia (padrão), a API pública do Kubernetes não permanece aberta à internet fora dessa janela; o sumário informa cluster, endpoint do Load Balancer Traefik e estado da Application.

## Estado do projeto

### Presente no repositório

- Código dos três microsserviços (`ngo-service`, `donation-service`, `volunteer-service`) com endpoints básicos de saúde e operação.
- Dockerfiles parametrizados para `linux/arm64` e arquivos de dependências.
- Scripts SQL iniciais para os bancos PostgreSQL dos serviços de ONGs e doações.
- Pipeline de CI e DevSecOps (`ci-apps.yml` e `_reusable-ci-devsecops.yml`) publicando no OCIR as imagens ARM64 dos serviços com tag canônica do SHA completo e `latest`, além de executar detecção seletiva de alterações (`Scope Discovery`), linters, análise estática de segurança (gosec, Bandit, Trivy) e scan de imagens.
- Base Kustomize em `k8s/base/` e overlay `k8s/overlays/oci-prod/` com Namespace, Deployments com probes, Services, Job de inicialização PostgreSQL, ConfigMap e Ingress Traefik, usando o namespace OCIR da tenancy.
- Application ArgoCD em `k8s/argocd/solidarytech-oci-prod.yaml` e bootstrap via Helm para ArgoCD e Traefik, com sincronização idempotente dos Secrets do OCI Vault para o namespace `solidarytech` durante cada execução.
- Job `update-gitops-manifests` no `ci-apps.yml` para atualizar apenas os serviços publicados com tags SHA completo e registrar a mudança por commit em `master` com `[skip ci]`; o CI de aplicações não acessa o cluster.
- Workflow manual `gitops-oke-bootstrap.yml` e bootstrap por outputs oficiais do Terraform; o comportamento em ambiente OCI/OKE não foi executado nesta validação local.
- Preflight automatizado de estado remoto (`infra/scripts/oci-state-preflight.sh`) com bucket `solidarytech-tfstate-prod` validado na OCI.
- Bootstrap idempotente e persistente do OCI Vault, Master Key, segredo de senha PostgreSQL e Auth Token OCIR (`infra/scripts/oci-secrets-preflight.sh`), executado pelo workflow de infraestrutura; o CI de aplicações apenas consome o token existente para publicar imagens.
- Módulos OCI de rede (`infra/modules/oci/network`) e Kubernetes/Registry (`infra/modules/oci/oke`), política IAM de serviço (`iam.tf`) e composição `infra/environments/oci-prod` validados via `terraform apply` e `terraform destroy` no GitHub Actions.
- Módulo PostgreSQL gerenciado (`infra/modules/oci/postgres`); conectividade privada entre OKE ARM64 (`10.0.2.0/24`) e PostgreSQL (`10.0.3.0/24:5432`) validada.
- Workflows de ciclo de vida da infraestrutura OCI (`infra-oci-lifecycle.yml` e `_reusable-terraform.yml`) com sumário de execução.
- Regras de governança de engenharia em [`AGENTS.md`](./AGENTS.md).

### Planejado, ainda não implementado aqui

- Camada Terraform da AWS (`infra/modules/aws` e `infra/environments/aws-dr`) para SQS/DLQ, DynamoDB e Warm Standby.
- Fase de Observabilidade & SRE (ACP-002), ainda não implementada:
  1. Prometheus, Loki e Grafana no namespace `observability`, via ArgoCD, com Grafana em `/grafana` pelo Traefik e senha administrada no OCI Vault.
  2. OpenTelemetry Collector para OTLP e instrumentação dos três microsserviços.
  3. Alertas HTTP 5xx, notificações Slack e Self-Healing via GitHub Actions.
  4. Trial do Datadog APM e Jira Service Management, com chaves e tokens gerenciados no OCI Vault.
- Rotação contínua dos Secrets sem nova execução do bootstrap.
- Docker Compose e configuração de ambiente de desenvolvimento local reproduzível.
- Testes automatizados funcionais dos microsserviços.
- SLIs/SLOs, AIOps e validação de Disaster Recovery.

