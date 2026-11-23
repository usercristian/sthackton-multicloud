# SolidaryTech — Arquitetura OCI, OKE, OCIR & ArgoCD

**Blueprint Visual da Plataforma Cloud-Native & GitOps na Oracle Cloud Infrastructure (`sa-saopaulo-1`)**

[Topologia](#1-topologia-cloud--kubernetes) •
[Mapa de Componentes](#2-mapa-de-componentes) •
[Fluxo GitOps & OCIR](#3-fluxo-gitops--ocir) •
[Cluster OKE & Workloads](#4-cluster-oke--workloads) •
[Ciclo de Vida ArgoCD](#5-ciclo-de-vida-argocd) •
[Matriz de Segurança](#6-matriz-de-segurança)

## 1. Topologia Cloud & Kubernetes

```mermaid
flowchart TB
    subgraph Internet["Camada Externa"]
        Client["Clientes / API Consumers"]
        Admin["Operador GitOps"]
        Git["GitHub (k8s/overlays/oci-prod)"]
        Actions["GitHub Actions (CI / Bootstrap)"]
    end

    subgraph OCI["OCI Region: sa-saopaulo-1"]
        Vault["OCI Vault<br/>solidarytech-vault-prod"]
        OCIR["OCIR Registry<br/>gru.ocir.io"]
        Bucket["Object Storage<br/>solidarytech-tfstate-prod"]

        subgraph VCN["VCN Isolada"]
            subgraph PubNet["Subnet Pública"]
                LB["OCI Load Balancer<br/>(Traefik Ingress)"]
            end

            subgraph PrivNet["Subnet Privada"]
                subgraph OKE["OKE Cluster (ARM64 - VM.Standard.A2.Flex)"]
                    Traefik["Traefik Proxy<br/>ns: traefik"]
                    Argo["ArgoCD<br/>ns: argocd (/argocd)"]

                    subgraph AppNS["ns: solidarytech"]
                        NGO["ngo-service :8081"]
                        DON["donation-service :8082"]
                        VOL["volunteer-service :8083"]
                        JOB["db-init Job"]
                    end
                end

                PG[("OCI PostgreSQL Privado<br/>DBs: ngos | donations")]
            end
        end
    end

    Client -->|HTTP :80| LB
    Admin -->|HTTP :80 /argocd| LB
    LB --> Traefik

    Traefik -->|/ngos| NGO
    Traefik -->|/donations| DON
    Traefik -->|/volunteers| VOL
    Traefik -->|/argocd| Argo

    NGO & DON --> PG
    JOB -->|psql gexec| PG

    Actions -->|State| Bucket
    Actions -->|Secrets| Vault
    Actions -->|Push SHA| OCIR
    Actions -->|Update Tag| Git

    Argo -->|Sync Manifests| Git
    Argo -->|Reconcile| AppNS
    OKE -->|Pull via ocir-secret| OCIR
```

## 2. Mapa de Componentes

```mermaid
mindmap
  root((SolidaryTech OCI))
    OKE Cluster
      Control Plane Gerenciado
      Node Pool ARM64 A2.Flex
      Runtime CRI-O Enforcing
    OCIR Registry
      Endpoint gru.ocir.io
      Imagens linux/arm64
      Tags Imutáveis Full SHA
      Auth via ocir-secret
    ArgoCD
      Application solidarytech-oci-prod
      Subpath /argocd via Traefik
      Kustomize LoadRestrictionsNone
      Senha bcrypt via OCI Vault
    Traefik Ingress
      OCI Public Load Balancer
      Roteamento PathPrefix
      Zero exposição direta de Pods
    Segurança & Vault
      solidarytech-vault-prod
      Regra 6443 efêmera no bootstrap
      PostgreSQL em subnet privada
```

| Domínio | Recurso | Identificador / Endpoint | Função |
| --- | --- | --- | --- |
| **OKE** | Cluster Kubernetes | `solidarytech-oke-cluster` | Orquestração de containers em nós ARM64 (`VM.Standard.A2.Flex`) |
| **OCIR** | Container Registry | `gru.ocir.io/<namespace>/solidarytech/*` | Armazenamento privado de imagens `linux/arm64` com tag `FULL_SHA` |
| **ArgoCD** | GitOps Controller | `solidarytech-oci-prod` (`/argocd`) | Reconciliação contínua entre `k8s/overlays/oci-prod` e o cluster |
| **Ingress** | Traefik + OCI LB | Subnet Pública (`:80`) | Ponto único de entrada HTTP para APIs e interface web do ArgoCD |
| **Vault** | Cofre de Segredos | `solidarytech-vault-prod` | Guarda token OCIR, credenciais PostgreSQL e senha admin do ArgoCD |
| **Dados** | PostgreSQL Privado | Subnet Privada (`:5432`) | Bancos `ngos` e `donations` isolados da internet |

## 3. Fluxo GitOps & OCIR

> [!NOTE]
> **Desacoplamento CI - CD:** O GitHub Actions nunca aplica manifestos de aplicação diretamente no OKE. Ele publica a imagem no **OCIR** (`gru.ocir.io`) e atualiza o SHA no Git; o **ArgoCD** detecta o commit e executa o rollout.

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Developer
    participant GH as GitHub (master)
    participant CI as ci-apps.yml
    participant OCIR as OCIR (gru.ocir.io)
    participant Argo as ArgoCD
    participant OKE as OKE Nodes (CRI-O)

    Dev->>GH: Push em services/**
    GH->>CI: Dispara build ARM64
    CI->>OCIR: docker buildx push :FULL_SHA
    CI->>GH: Commit [skip ci] em kustomization.yaml
    Argo->>GH: Polling / Detecção de novo SHA
    Argo->>OKE: Aplica Deployment atualizado
    OKE->>OCIR: Pull autenticado (ocir-secret @ gru.ocir.io)
    OCIR-->>OKE: Imagem ARM64 verificada
    OKE-->>Argo: RollingUpdate concluído (1/1 Ready)
```

## 4. Cluster OKE & Workloads

```mermaid
graph LR
    subgraph IngressLayer["Roteamento Traefik"]
        R1["/ngos/*"]
        R2["/donations/*"]
        R3["/volunteers/*"]
        R4["/argocd/*"]
    end

    subgraph Namespaces["Namespaces OKE"]
        subgraph NS1["ns: solidarytech"]
            S1["Service :8081"] --> D1["Deployment: ngo-service"]
            S2["Service :8082"] --> D2["Deployment: donation-service"]
            S3["Service :8083"] --> D3["Deployment: volunteer-service"]
            J1["Job: db-init (docker.io/library/postgres:15-alpine)"]
            SA["ServiceAccount: default + ocir-secret"]
        end

        subgraph NS2["ns: argocd"]
            S4["Service: argocd-server :80"] --> D4["ArgoCD Server & Repo Server"]
        end
    end

    R1 --> S1
    R2 --> S2
    R3 --> S3
    R4 --> S4
    SA -.-> D1 & D2 & D3
```

### Contratos Técnicos do Runtime OKE

| Regra de Runtime | Configuração Aplicada | Motivo Técnico |
| --- | --- | --- |
| **Fully Qualified Images** | `docker.io/library/...` e `gru.ocir.io/...` | CRI-O no Oracle Linux opera com `short-name-mode = "enforcing"` |
| **Alinhamento OCIR** | `--docker-server=gru.ocir.io` no `ocir-secret` | Kubelet exige correspondência exata entre o host da imagem e o Secret |
| **Histórico Limpo** | `revisionHistoryLimit: 1` nos Deployments | Evita acúmulo de ReplicaSets inativos (`0/0`) no painel do ArgoCD |
| **Gunicorn Non-Root** | `ENV HOME=/tmp` nos Dockerfiles Python | Permite criação do socket de controle do Gunicorn 27 sem privilégios |
| **DB Init Idempotente** | `SELECT ... \gexec` no Job `db-init` | Cria `ngos` e `donations` condicionalmente antes de aplicar schemas |

## 5. Ciclo de Vida ArgoCD

```mermaid
stateDiagram-v2
    [*] --> Bootstrap: gitops-oke-bootstrap.yml
    Bootstrap --> SecretSync: Lê Vault & injeta bcrypt em argocd-secret
    SecretSync --> AppCreated: Aplica k8s/argocd/solidarytech-oci-prod.yaml
    AppCreated --> Syncing: Kustomize renderiza overlay oci-prod
    Syncing --> Healthy: Pods 1/1 Running & Jobs Completed
    Healthy --> OutOfSync: Novo commit SHA no Git
    OutOfSync --> Syncing: Auto-Sync & Self-Heal
```

| Parâmetro ArgoCD | Valor Configurado | Onde é Definido |
| --- | --- | --- |
| **Application** | `solidarytech-oci-prod` | `k8s/argocd/solidarytech-oci-prod.yaml` |
| **Source Path** | `k8s/overlays/oci-prod` | `k8s/argocd/solidarytech-oci-prod.yaml` |
| **Root Path Web** | `/argocd` (`configs.params."server.rootpath"`) | `infra/scripts/oci-oke-gitops-bootstrap.sh` |
| **Kustomize Options** | `--load-restrictor LoadRestrictionsNone` | `infra/scripts/oci-oke-gitops-bootstrap.sh` |
| **Admin Password** | Hash `bcrypt` do segredo `solidarytech-argocd-admin-password` | `infra/scripts/oci-oke-gitops-bootstrap.sh` |

## 6. Matriz de Segurança

> [!IMPORTANT]
> **Zero-Trust na API Kubernetes:** A porta `TCP/6443` permanece bloqueada na Security List `solidarytech-sl-public-lb`. Durante o bootstrap ou destroy, o GitHub Actions libera apenas o IPv4 efêmero do runner (`temp-gh-runner-<run_id>-<attempt>`), limpa regras órfãs e revoga o acesso em `if: always()`.

| Camada | Controle Implementado | Evidência no Repositório |
| --- | --- | --- |
| **Segredos** | Zero credenciais no Git ou logs; leitura dinâmica do **OCI Vault** | `infra/scripts/oci-secrets-preflight.sh` |
| **Rede API** | Liberação temporária e autorrevogável de `TCP/6443` por IP do runner | `.github/workflows/gitops-oke-bootstrap.yml` |
| **Banco de Dados** | PostgreSQL isolado em subnet privada sem IP público | `infra/modules/oci/` |
| **Supply Chain** | Imagens privadas no OCIR puxadas por `FULL_SHA` imutável | `k8s/overlays/oci-prod/kustomization.yaml` |
| **Hardening Pods** | `allowPrivilegeEscalation: false` e `capabilities.drop: ["ALL"]` no `db-init` | `k8s/base/db-init-job.yaml` |
| **FinOps & Estado** | Vault e OCIR desacoplados do `terraform destroy` (`removed { destroy = false }`) | `infra/environments/oci-prod/` |