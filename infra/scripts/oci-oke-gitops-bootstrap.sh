#!/usr/bin/env bash
set -euo pipefail
set +x

: "${OCI_CLI_COMPARTMENT:?Variável OCI_CLI_COMPARTMENT não definida}"
: "${OCI_CLI_USER:?Variável OCI_CLI_USER não definida}"
: "${OCI_CLI_REGION:=sa-saopaulo-1}"
: "${OKE_CLUSTER_ID:?Variável OKE_CLUSTER_ID não definida}"
: "${POSTGRES_PRIVATE_IP:?Variável POSTGRES_PRIVATE_IP não definida}"
: "${POSTGRES_ADMIN_USERNAME:?Variável POSTGRES_ADMIN_USERNAME não definida}"

VAULT_NAME="solidarytech-vault-prod"
OCIR_SECRET_NAME="solidarytech-ocir-token"
DB_SECRET_NAME="solidarytech-postgres-password"
ARGOCD_ADMIN_PASSWORD_SECRET_NAME="solidarytech-argocd-admin-password"
GRAFANA_ADMIN_PASSWORD_SECRET_NAME="solidarytech-grafana-admin-password"
POSTGRES_USER="${POSTGRES_ADMIN_USERNAME}"
POSTGRES_PORT="5432"

cleanup() {
  unset OCIR_TOKEN DB_PASSWORD
  unset DB_PASSWORD_URLENCODED NGO_DATABASE_URL DONATION_DATABASE_URL
  unset ARGOCD_ADMIN_PASSWORD ARGOCD_ADMIN_PASSWORD_HASH GRAFANA_ADMIN_PASSWORD
  unset EXISTING_ADMIN_PASSWORD_HASH EXISTING_ADMIN_PASSWORD_HASH_BASE64
  unset ARGOCD_SECRET_JSON
  if [[ -n "${ARGOCD_SECRET_PATCH_FILE:-}" ]]; then
    rm -f -- "${ARGOCD_SECRET_PATCH_FILE}"
  fi
}
trap cleanup EXIT

for command in oci jq base64 python3 helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERRO: Dependência obrigatória não encontrada: ${command}" >&2
    exit 1
  fi
done

if ! python3 -c 'import ipaddress, sys; ipaddress.ip_address(sys.argv[1])' \
  "${POSTGRES_PRIVATE_IP}" >/dev/null 2>&1; then
  echo "ERRO: POSTGRES_PRIVATE_IP não contém um endereço IP válido." >&2
  exit 1
fi

echo "Validando cluster OKE pelo ID informado..."
CLUSTER=$(oci --auth api_key --region "${OCI_CLI_REGION}" ce cluster get \
  --cluster-id "${OKE_CLUSTER_ID}" \
  --query 'data')
CLUSTER_STATE=$(jq -r '."lifecycle-state"' <<<"${CLUSTER}")
CLUSTER_COMPARTMENT=$(jq -r '."compartment-id"' <<<"${CLUSTER}")
if [[ "${CLUSTER_STATE}" != "ACTIVE" ]]; then
  echo "ERRO: Cluster OKE não está ACTIVE (estado: ${CLUSTER_STATE})." >&2
  exit 1
fi
if [[ "${CLUSTER_COMPARTMENT}" != "${OCI_CLI_COMPARTMENT}" ]]; then
  echo "ERRO: O cluster OKE pertence a um compartment diferente do configurado." >&2
  exit 1
fi

echo "Cluster OKE ativo e validado; carregando o Vault..."
VAULTS=$(oci --auth api_key --region "${OCI_CLI_REGION}" kms management vault list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --all \
  --query 'data')
MATCHING_VAULTS=$(jq -c --arg name "${VAULT_NAME}" \
  '[.[] | select(."display-name" == $name)]' <<<"${VAULTS}")
VAULT_COUNT=$(jq 'length' <<<"${MATCHING_VAULTS}")
if [[ "${VAULT_COUNT}" -ne 1 ]]; then
  echo "ERRO: Esperado exatamente um Vault '${VAULT_NAME}'; encontrados: ${VAULT_COUNT}." >&2
  exit 1
fi

VAULT_ID=$(jq -r '.[0].id' <<<"${MATCHING_VAULTS}")
VAULT=$(oci --auth api_key --region "${OCI_CLI_REGION}" kms management vault get \
  --vault-id "${VAULT_ID}" \
  --query 'data')
VAULT_STATE=$(jq -r '."lifecycle-state"' <<<"${VAULT}")
if [[ "${VAULT_STATE}" != "ACTIVE" ]]; then
  echo "ERRO: Vault '${VAULT_NAME}' não está ACTIVE (estado: ${VAULT_STATE})." >&2
  exit 1
fi

get_secret_value() {
  local secret_name="$1"
  local encoded_content

  encoded_content=$(oci --auth api_key --region "${OCI_CLI_REGION}" \
    secrets secret-bundle get-secret-bundle-by-name \
    --vault-id "${VAULT_ID}" \
    --secret-name "${secret_name}" \
    --stage CURRENT \
    --query 'data."secret-bundle-content".content' \
    --raw-output)
  if [[ -z "${encoded_content}" || "${encoded_content}" == "null" ]]; then
    echo "ERRO: Conteúdo do secret '${secret_name}' não foi retornado." >&2
    return 1
  fi
  printf '%s' "${encoded_content}" | base64 --decode
}

OCIR_TOKEN=$(get_secret_value "${OCIR_SECRET_NAME}")
DB_PASSWORD=$(get_secret_value "${DB_SECRET_NAME}")
if [[ -z "${OCIR_TOKEN}" || -z "${DB_PASSWORD}" ]]; then
  echo "ERRO: Auth Token do OCIR ou senha PostgreSQL está vazio." >&2
  exit 1
fi

OCI_USERNAME=$(oci --auth api_key --region "${OCI_CLI_REGION}" iam user get \
  --user-id "${OCI_CLI_USER}" \
  --query 'data.name' \
  --raw-output)
TENANCY_NAMESPACE=$(oci --auth api_key --region "${OCI_CLI_REGION}" os ns get \
  --query 'data' \
  --raw-output)
if [[ -z "${OCI_USERNAME}" || -z "${TENANCY_NAMESPACE}" ]]; then
  echo "ERRO: Usuário OCI ou namespace da tenancy não foi retornado." >&2
  exit 1
fi

DB_HOST="${POSTGRES_PRIVATE_IP}"

DB_PASSWORD_URLENCODED=$(DB_PASSWORD="${DB_PASSWORD}" python3 -c \
  'import os; from urllib.parse import quote; print(quote(os.environ["DB_PASSWORD"], safe=""))')
NGO_DATABASE_URL="postgresql://${POSTGRES_USER}:${DB_PASSWORD_URLENCODED}@${DB_HOST}:${POSTGRES_PORT}/ngos"
DONATION_DATABASE_URL="postgresql://${POSTGRES_USER}:${DB_PASSWORD_URLENCODED}@${DB_HOST}:${POSTGRES_PORT}/donations"

mkdir -p "${HOME}/.kube"
chmod 700 "${HOME}/.kube"
oci --auth api_key --region "${OCI_CLI_REGION}" ce cluster create-kubeconfig \
  --cluster-id "${OKE_CLUSTER_ID}" \
  --file "${HOME}/.kube/config" \
  --overwrite \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT
chmod 600 "${HOME}/.kube/config"

API_READY=0
for attempt in {1..36}; do
  if kubectl get --raw='/readyz' >/dev/null; then
    API_READY=1
    break
  fi
  echo "API Kubernetes ainda não está pronta (tentativa ${attempt}/36); aguardando 5s."
  sleep 5
done
if [[ "${API_READY}" -ne 1 ]]; then
  echo "ERRO: API Kubernetes não ficou pronta após 180 segundos." >&2
  exit 1
fi

kubectl wait --for=condition=Ready nodes --all --timeout=180s
NODES=$(kubectl get nodes -o json)
NODE_COUNT=$(jq '.items | length' <<<"${NODES}")
NON_ARM64_COUNT=$(jq '[.items[] | select(.status.nodeInfo.architecture != "arm64")] | length' \
  <<<"${NODES}")
if [[ "${NODE_COUNT}" -eq 0 || "${NON_ARM64_COUNT}" -ne 0 ]]; then
  echo "ERRO: Esperados nós ARM64 Ready; encontrados ${NODE_COUNT} nós e ${NON_ARM64_COUNT} com arquitetura diferente." >&2
  exit 1
fi

echo "Instalando ou atualizando Traefik e ArgoCD..."
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update

helm upgrade --install traefik traefik/traefik \
  --version 43.0.0 \
  --namespace traefik \
  --create-namespace \
  --set deployment.replicas=1 \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=128Mi \
  --set metrics.prometheus.entryPoint=metrics \
  --set metrics.prometheus.addEntryPointsLabels=true \
  --set ports.metrics.enabled=true \
  --set ports.metrics.port=9100 \
  --set metrics.prometheus.service.enabled=true \
  --set metrics.prometheus.serviceMonitor.enabled=false \
  --wait \
  --timeout 10m

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set 'configs.params.server\.insecure=true' \
  --set-string 'configs.params.server\.rootpath=/argocd' \
  --set-string 'configs.cm.kustomize\.buildOptions=--load-restrictor LoadRestrictionsNone' \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  --set applicationSet.enabled=false \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.resources.limits.cpu=250m \
  --set controller.resources.limits.memory=512Mi \
  --set repoServer.resources.requests.cpu=100m \
  --set repoServer.resources.requests.memory=256Mi \
  --set repoServer.resources.limits.cpu=250m \
  --set repoServer.resources.limits.memory=512Mi \
  --set server.resources.requests.cpu=50m \
  --set server.resources.requests.memory=128Mi \
  --set server.resources.limits.cpu=150m \
  --set server.resources.limits.memory=256Mi \
  --set redis.resources.requests.cpu=25m \
  --set redis.resources.requests.memory=64Mi \
  --set redis.resources.limits.cpu=100m \
  --set redis.resources.limits.memory=128Mi \
  --wait \
  --timeout 10m

kubectl create namespace solidarytech --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret docker-registry ocir-secret \
  --namespace solidarytech \
  --docker-server="gru.ocir.io" \
  --docker-username="${TENANCY_NAMESPACE}/${OCI_USERNAME}" \
  --docker-password="${OCIR_TOKEN}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -
kubectl -n solidarytech patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"ocir-secret"}]}' \
  >/dev/null
kubectl create secret generic solidarytech-db-secret \
  --namespace solidarytech \
  --from-literal="POSTGRES_HOST=${DB_HOST}" \
  --from-literal="POSTGRES_PORT=${POSTGRES_PORT}" \
  --from-literal="POSTGRES_USER=${POSTGRES_USER}" \
  --from-literal="POSTGRES_PASSWORD=${DB_PASSWORD}" \
  --from-literal="NGO_DATABASE_URL=${NGO_DATABASE_URL}" \
  --from-literal="DONATION_DATABASE_URL=${DONATION_DATABASE_URL}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -
unset OCIR_TOKEN DB_PASSWORD
unset DB_PASSWORD_URLENCODED NGO_DATABASE_URL DONATION_DATABASE_URL

kubectl rollout status deployment/argocd-server --namespace argocd --timeout=10m
kubectl rollout status deployment/argocd-repo-server --namespace argocd --timeout=10m
kubectl rollout status statefulset/argocd-application-controller --namespace argocd --timeout=10m
kubectl rollout status deployment/argocd-redis --namespace argocd --timeout=10m

ARGOCD_ADMIN_PASSWORD=$(get_secret_value "${ARGOCD_ADMIN_PASSWORD_SECRET_NAME}")
if [[ -z "${ARGOCD_ADMIN_PASSWORD}" ]]; then
  echo "ERRO: A senha administrativa do ArgoCD retornada pelo Vault está vazia." >&2
  exit 1
fi

if ! python3 -c 'import bcrypt' >/dev/null 2>&1; then
  python3 -m pip install --quiet --disable-pip-version-check bcrypt
fi

ARGOCD_SECRET_JSON=$(kubectl -n argocd get secret argocd-secret -o json)
EXISTING_ADMIN_PASSWORD_HASH_BASE64=$(jq -r '.data["admin.password"] // empty' \
  <<<"${ARGOCD_SECRET_JSON}")
EXISTING_ADMIN_PASSWORD_HASH=""
if [[ -n "${EXISTING_ADMIN_PASSWORD_HASH_BASE64}" ]]; then
  EXISTING_ADMIN_PASSWORD_HASH=$(printf '%s' "${EXISTING_ADMIN_PASSWORD_HASH_BASE64}" \
    | base64 --decode)
fi
EXISTING_ADMIN_PASSWORD_MTIME=$(jq -r '.data["admin.passwordMtime"] // empty' \
  <<<"${ARGOCD_SECRET_JSON}")

PASSWORD_HASH_MATCH="false"
if [[ -n "${EXISTING_ADMIN_PASSWORD_HASH}" ]]; then
  PASSWORD_HASH_MATCH=$( \
    ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD}" \
    EXISTING_ADMIN_PASSWORD_HASH="${EXISTING_ADMIN_PASSWORD_HASH}" \
    python3 - <<'PY'
import os
import bcrypt

try:
    matches = bcrypt.checkpw(
        os.environ["ARGOCD_ADMIN_PASSWORD"].encode(),
        os.environ["EXISTING_ADMIN_PASSWORD_HASH"].encode(),
    )
except (TypeError, ValueError):
    matches = False
print("true" if matches else "false")
PY
  )
fi

if [[ "${PASSWORD_HASH_MATCH}" != "true" || -z "${EXISTING_ADMIN_PASSWORD_MTIME}" ]]; then
  if [[ "${PASSWORD_HASH_MATCH}" == "true" ]]; then
    ARGOCD_ADMIN_PASSWORD_HASH="${EXISTING_ADMIN_PASSWORD_HASH}"
  else
    ARGOCD_ADMIN_PASSWORD_HASH=$( \
      ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD}" \
      python3 -c 'import bcrypt, os; print(bcrypt.hashpw(os.environ["ARGOCD_ADMIN_PASSWORD"].encode(), bcrypt.gensalt()).decode("ascii"))'
    )
  fi
  if [[ -z "${ARGOCD_ADMIN_PASSWORD_HASH}" ]]; then
    echo "ERRO: Não foi possível gerar/verificar o hash administrativo do ArgoCD." >&2
    exit 1
  fi

  ARGOCD_SECRET_PATCH_FILE=$(mktemp "${TMPDIR:-/tmp}/argocd-secret-patch.XXXXXX")
  chmod 600 "${ARGOCD_SECRET_PATCH_FILE}"
  ARGOCD_ADMIN_PASSWORD_HASH="${ARGOCD_ADMIN_PASSWORD_HASH}" \
    ADMIN_PASSWORD_MTIME="$(date -u +%FT%TZ)" \
    python3 - "${ARGOCD_SECRET_PATCH_FILE}" <<'PY'
import json
import os
import sys
from pathlib import Path

patch = {
    "stringData": {
        "admin.password": os.environ["ARGOCD_ADMIN_PASSWORD_HASH"],
        "admin.passwordMtime": os.environ["ADMIN_PASSWORD_MTIME"],
    }
}
Path(sys.argv[1]).write_text(json.dumps(patch))
PY
  kubectl -n argocd patch secret argocd-secret \
    --type=merge \
    --patch-file "${ARGOCD_SECRET_PATCH_FILE}" \
    >/dev/null
else
  echo "Senha administrativa do ArgoCD já sincronizada; hash preservado."
fi

kubectl -n argocd delete secret argocd-initial-admin-secret \
  --ignore-not-found \
  >/dev/null
unset ARGOCD_ADMIN_PASSWORD ARGOCD_ADMIN_PASSWORD_HASH
unset EXISTING_ADMIN_PASSWORD_HASH EXISTING_ADMIN_PASSWORD_HASH_BASE64
unset ARGOCD_SECRET_JSON

kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f - >/dev/null
GRAFANA_ADMIN_PASSWORD=$(get_secret_value "${GRAFANA_ADMIN_PASSWORD_SECRET_NAME}")
if [[ -z "${GRAFANA_ADMIN_PASSWORD}" ]]; then
  echo "ERRO: A senha administrativa do Grafana retornada pelo Vault está vazia." >&2
  exit 1
fi

GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}" python3 - <<'PY' | kubectl apply -f - >/dev/null
import json
import os

print(json.dumps({
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": {
        "name": "grafana-admin-secret",
        "namespace": "observability",
    },
    "type": "Opaque",
    "stringData": {
        "admin-user": "admin",
        "admin-password": os.environ["GRAFANA_ADMIN_PASSWORD"],
    },
}))
PY
unset GRAFANA_ADMIN_PASSWORD

echo "Instalando ou atualizando os CRDs do Prometheus Operator..."
PROMETHEUS_OPERATOR_CRDS=(
  alertmanagerconfigs.monitoring.coreos.com
  alertmanagers.monitoring.coreos.com
  podmonitors.monitoring.coreos.com
  probes.monitoring.coreos.com
  prometheusagents.monitoring.coreos.com
  prometheuses.monitoring.coreos.com
  prometheusrules.monitoring.coreos.com
  scrapeconfigs.monitoring.coreos.com
  servicemonitors.monitoring.coreos.com
  thanosrulers.monitoring.coreos.com
)

# Adota apenas CRDs v0.95.2 sem proprietário de outro release Helm ou Application ArgoCD.
for crd in "${PROMETHEUS_OPERATOR_CRDS[@]}"; do
  if ! CRD_JSON=$(kubectl get crd "${crd}" --ignore-not-found -o json); then
    echo "ERRO: Não foi possível consultar o CRD '${crd}' para validar sua propriedade." >&2
    exit 1
  fi
  if [[ -z "${CRD_JSON}" || "${CRD_JSON}" == "null" ]]; then
    continue
  fi

  CRD_OWNERSHIP=$(jq -r '[
    .metadata.labels["app.kubernetes.io/managed-by"] // "",
    .metadata.annotations["meta.helm.sh/release-name"] // "",
    .metadata.annotations["meta.helm.sh/release-namespace"] // "",
    .metadata.annotations["operator.prometheus.io/version"] // "",
    .metadata.annotations["argocd.argoproj.io/tracking-id"] // "",
    .metadata.labels["app.kubernetes.io/instance"] // "",
    .metadata.labels["argocd.argoproj.io/instance"] // ""
  ] | join("|")' <<<"${CRD_JSON}")
  IFS='|' read -r CRD_MANAGED_BY CRD_HELM_RELEASE CRD_HELM_NAMESPACE \
    CRD_OPERATOR_VERSION CRD_ARGO_TRACKING_ID CRD_APP_INSTANCE CRD_ARGO_INSTANCE \
    <<<"${CRD_OWNERSHIP}"

  if [[ -n "${CRD_MANAGED_BY}" && "${CRD_MANAGED_BY}" != "Helm" ]]; then
    echo "ERRO: CRD '${crd}' pertence a '${CRD_MANAGED_BY}', não será transferido ao Helm." >&2
    exit 1
  fi
  if [[ -n "${CRD_HELM_RELEASE}" && "${CRD_HELM_RELEASE}" != "prometheus-operator-crds" ]] ||
    [[ -n "${CRD_HELM_NAMESPACE}" && "${CRD_HELM_NAMESPACE}" != "observability" ]]; then
    echo "ERRO: CRD '${crd}' contém metadados de outro release Helm; não será transferido." >&2
    exit 1
  fi
  if [[ "${CRD_OPERATOR_VERSION}" != "0.95.2" ]]; then
    echo "ERRO: CRD '${crd}' não declara a versão esperada do Operator (0.95.2); não será transferido." >&2
    exit 1
  fi
  if [[ -n "${CRD_ARGO_TRACKING_ID}" &&
    "${CRD_ARGO_TRACKING_ID}" != "solidarytech-observability-oci:"* ]]; then
    echo "ERRO: CRD '${crd}' está associado a outra Application ArgoCD; não será transferido." >&2
    exit 1
  fi
  if [[ -n "${CRD_APP_INSTANCE}" &&
    "${CRD_APP_INSTANCE}" != "solidarytech-observability-oci" &&
    "${CRD_APP_INSTANCE}" != "kube-prometheus-stack" ]]; then
    echo "ERRO: CRD '${crd}' está associado a outra instância; não será transferido." >&2
    exit 1
  fi
  if [[ -n "${CRD_ARGO_INSTANCE}" &&
    "${CRD_ARGO_INSTANCE}" != "solidarytech-observability-oci" ]]; then
    echo "ERRO: CRD '${crd}' está associado a outra Application ArgoCD; não será transferido." >&2
    exit 1
  fi

  echo "Transferindo a propriedade do CRD existente '${crd}' para o release Helm..."
  kubectl label crd "${crd}" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null
  kubectl annotate crd "${crd}" \
    meta.helm.sh/release-name=prometheus-operator-crds \
    meta.helm.sh/release-namespace=observability \
    --overwrite >/dev/null
  if [[ -n "${CRD_APP_INSTANCE}" ]]; then
    kubectl label crd "${crd}" app.kubernetes.io/instance- >/dev/null
  fi
  if [[ -n "${CRD_ARGO_INSTANCE}" ]]; then
    kubectl label crd "${crd}" argocd.argoproj.io/instance- >/dev/null
  fi
  if [[ -n "${CRD_ARGO_TRACKING_ID}" ]]; then
    kubectl annotate crd "${crd}" argocd.argoproj.io/tracking-id- >/dev/null
  fi
done

helm upgrade --install prometheus-operator-crds prometheus-community/prometheus-operator-crds \
  --version 33.0.2 \
  --namespace observability \
  --wait \
  --timeout 10m

kubectl apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
spec:
  ingressClassName: traefik
  rules:
    - http:
        paths:
          - path: /argocd
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
YAML

kubectl apply -f k8s/argocd/solidarytech-oci-prod.yaml
kubectl apply -f k8s/argocd/solidarytech-observability-oci.yaml

echo "Bootstrap GitOps concluído."
