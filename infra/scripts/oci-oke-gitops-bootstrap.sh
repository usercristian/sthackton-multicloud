#!/usr/bin/env bash
set -euo pipefail
set +x

: "${OCI_CLI_COMPARTMENT:?Variável OCI_CLI_COMPARTMENT não definida}"
: "${OCI_CLI_USER:?Variável OCI_CLI_USER não definida}"
: "${OCI_CLI_REGION:=sa-saopaulo-1}"

VAULT_NAME="solidarytech-vault-prod"
OCIR_SECRET_NAME="solidarytech-ocir-token"
DB_SECRET_NAME="solidarytech-postgres-password"
CLUSTER_NAME="solidarytech-oke-prod"
DB_SYSTEM_NAME="solidarytech-postgres-prod"
REGISTRY="sa-saopaulo-1.ocir.io"
POSTGRES_USER="solidaryadmin"
POSTGRES_PORT="5432"

cleanup() {
  unset OCIR_TOKEN DB_PASSWORD
  unset DB_PASSWORD_URLENCODED NGO_DATABASE_URL DONATION_DATABASE_URL
}
trap cleanup EXIT

for command in oci jq base64 python3 helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERRO: Dependência obrigatória não encontrada: ${command}" >&2
    exit 1
  fi
done

echo "Localizando cluster OKE, Vault e DB System..."

CLUSTERS=$(oci --auth api_key --region "${OCI_CLI_REGION}" ce cluster list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --all \
  --query 'data')
MATCHING_CLUSTERS=$(jq -c --arg name "${CLUSTER_NAME}" \
  '[.[] | select(.name == $name)]' <<<"${CLUSTERS}")
CLUSTER_COUNT=$(jq 'length' <<<"${MATCHING_CLUSTERS}")
if [[ "${CLUSTER_COUNT}" -ne 1 ]]; then
  echo "ERRO: Esperado exatamente um cluster '${CLUSTER_NAME}'; encontrados: ${CLUSTER_COUNT}." >&2
  exit 1
fi

CLUSTER_ID=$(jq -r '.[0].id' <<<"${MATCHING_CLUSTERS}")
CLUSTER_STATE=$(jq -r '.[0]."lifecycle-state"' <<<"${MATCHING_CLUSTERS}")
if [[ "${CLUSTER_STATE}" != "ACTIVE" ]]; then
  echo "ERRO: Cluster '${CLUSTER_NAME}' não está ACTIVE (estado: ${CLUSTER_STATE})." >&2
  exit 1
fi

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

DB_SYSTEMS=$(oci --auth api_key --region "${OCI_CLI_REGION}" psql db-system list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --all \
  --query 'data')
MATCHING_DB_SYSTEMS=$(jq -c --arg name "${DB_SYSTEM_NAME}" \
  '[.[] | select(."display-name" == $name and ."lifecycle-state" == "ACTIVE")]' \
  <<<"${DB_SYSTEMS}")
DB_SYSTEM_COUNT=$(jq 'length' <<<"${MATCHING_DB_SYSTEMS}")
if [[ "${DB_SYSTEM_COUNT}" -ne 1 ]]; then
  echo "ERRO: Esperado exatamente um DB System ativo '${DB_SYSTEM_NAME}'; encontrados: ${DB_SYSTEM_COUNT}." >&2
  exit 1
fi

DB_SYSTEM_ID=$(jq -r '.[0].id' <<<"${MATCHING_DB_SYSTEMS}")
DB_SYSTEM=$(oci --auth api_key --region "${OCI_CLI_REGION}" psql db-system get \
  --db-system-id "${DB_SYSTEM_ID}" \
  --query 'data')
DB_HOST=$(jq -r '."network-details"[0]."primary-db-endpoint-private-ip" // empty' \
  <<<"${DB_SYSTEM}")
if [[ -z "${DB_HOST}" || "${DB_HOST}" == "null" ]]; then
  echo "ERRO: DB System '${DB_SYSTEM_NAME}' não retornou o IP privado do endpoint." >&2
  exit 1
fi

DB_PASSWORD_URLENCODED=$(DB_PASSWORD="${DB_PASSWORD}" python3 -c \
  'import os; from urllib.parse import quote; print(quote(os.environ["DB_PASSWORD"], safe=""))')
NGO_DATABASE_URL="postgresql://${POSTGRES_USER}:${DB_PASSWORD_URLENCODED}@${DB_HOST}:${POSTGRES_PORT}/ngos"
DONATION_DATABASE_URL="postgresql://${POSTGRES_USER}:${DB_PASSWORD_URLENCODED}@${DB_HOST}:${POSTGRES_PORT}/donations"

mkdir -p "${HOME}/.kube"
chmod 700 "${HOME}/.kube"
oci --auth api_key --region "${OCI_CLI_REGION}" ce cluster create-kubeconfig \
  --cluster-id "${CLUSTER_ID}" \
  --file "${HOME}/.kube/config" \
  --overwrite \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT

echo "Instalando ou atualizando ingress-nginx e ArgoCD..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=1 \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=128Mi \
  --set controller.resources.limits.cpu=250m \
  --set controller.resources.limits.memory=256Mi \
  --wait \
  --timeout 10m

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set 'configs.params.server\.insecure=true' \
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
  --docker-server="${REGISTRY}" \
  --docker-username="${TENANCY_NAMESPACE}/${OCI_USERNAME}" \
  --docker-password="${OCIR_TOKEN}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -
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
kubectl apply -f k8s/argocd/solidarytech-oci-prod.yaml

echo "Bootstrap GitOps concluído."
