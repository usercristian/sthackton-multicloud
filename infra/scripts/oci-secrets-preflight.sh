#!/usr/bin/env bash
set -euo pipefail
set +x

: "${OCI_CLI_COMPARTMENT:?Variável OCI_CLI_COMPARTMENT não definida}"
: "${OCI_CLI_USER:?Variável OCI_CLI_USER não definida}"
: "${OCI_CLI_REGION:=sa-saopaulo-1}"

VAULT_NAME="solidarytech-vault-prod"
KEY_NAME="solidarytech-master-key"
SECRET_NAME="solidarytech-postgres-password"
OCIR_SECRET_NAME="solidarytech-ocir-token"
ARGOCD_ADMIN_SECRET_NAME="solidarytech-argocd-admin-password"
FINOPS_TAGS='{"Project":"Solidary Tech","Environment":"Production","CostCenter":"NGO-Core","ManagedBy":"CI-Preflight"}'
trap 'unset GENERATED_PASSWORD SECRET_CONTENT_BASE64 GENERATED_OCIR_TOKEN OCIR_SECRET_CONTENT_BASE64 GENERATED_ARGOCD_ADMIN_PASSWORD ARGOCD_ADMIN_SECRET_CONTENT_BASE64' EXIT

for command in oci jq openssl base64 tr cut; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERRO: Dependência obrigatória não encontrada: ${command}" >&2
    exit 1
  fi
done

echo "Iniciando preflight de secrets OCI Vault (região: ${OCI_CLI_REGION})..."

VAULTS=$(oci --auth api_key --region "${OCI_CLI_REGION}" kms management vault list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --all \
  --query 'data')
MATCHING_VAULTS=$(jq -c --arg name "${VAULT_NAME}" \
  '[.[] | select(."display-name" == $name)]' <<<"${VAULTS}")
VAULT_COUNT=$(jq 'length' <<<"${MATCHING_VAULTS}")

if [[ "${VAULT_COUNT}" -gt 1 ]]; then
  echo "ERRO: Mais de um Vault '${VAULT_NAME}' foi encontrado no compartment." >&2
  exit 1
fi

if [[ "${VAULT_COUNT}" -eq 0 ]]; then
  echo "Vault '${VAULT_NAME}' não encontrado. Criando..."
  VAULT_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" kms management vault create \
    --compartment-id "${OCI_CLI_COMPARTMENT}" \
    --display-name "${VAULT_NAME}" \
    --vault-type DEFAULT \
    --freeform-tags "${FINOPS_TAGS}" \
    --query 'data')
  VAULT_ID=$(jq -r '.id' <<<"${VAULT_JSON}")
else
  VAULT_ID=$(jq -r '.[0].id' <<<"${MATCHING_VAULTS}")
fi

VAULT_STATE=""
for attempt in {1..120}; do
  VAULT_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" kms management vault get \
    --vault-id "${VAULT_ID}" \
    --query 'data')
  VAULT_STATE=$(jq -r '."lifecycle-state"' <<<"${VAULT_JSON}")
  if [[ "${VAULT_STATE}" == "ACTIVE" ]]; then
    break
  fi
  if [[ "${VAULT_STATE}" == "FAILED" || "${attempt}" -eq 120 ]]; then
    echo "ERRO: Vault '${VAULT_NAME}' não atingiu ACTIVE (estado: ${VAULT_STATE})." >&2
    exit 1
  fi
  sleep 10
done

VAULT_TYPE=$(jq -r '."vault-type"' <<<"${VAULT_JSON}")
if [[ "${VAULT_TYPE}" != "DEFAULT" ]]; then
  echo "ERRO: Vault '${VAULT_NAME}' é do tipo '${VAULT_TYPE}', esperado DEFAULT." >&2
  exit 1
fi

MANAGEMENT_ENDPOINT=$(jq -r '."management-endpoint"' <<<"${VAULT_JSON}")
if [[ -z "${MANAGEMENT_ENDPOINT}" || "${MANAGEMENT_ENDPOINT}" == "null" ]]; then
  echo "ERRO: O Vault ativo não retornou um management-endpoint." >&2
  exit 1
fi
echo "Vault '${VAULT_NAME}' ativo."

KEYS=$(oci --auth api_key --region "${OCI_CLI_REGION}" --endpoint "${MANAGEMENT_ENDPOINT}" \
  kms management key list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --all \
  --query 'data')
MATCHING_KEYS=$(jq -c --arg name "${KEY_NAME}" \
  '[.[] | select(."display-name" == $name)]' <<<"${KEYS}")
KEY_COUNT=$(jq 'length' <<<"${MATCHING_KEYS}")

if [[ "${KEY_COUNT}" -gt 1 ]]; then
  echo "ERRO: Mais de uma chave '${KEY_NAME}' foi encontrada no Vault." >&2
  exit 1
fi

if [[ "${KEY_COUNT}" -eq 0 ]]; then
  echo "Chave '${KEY_NAME}' não encontrada. Criando..."
  KEY_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" --endpoint "${MANAGEMENT_ENDPOINT}" \
    kms management key create \
    --compartment-id "${OCI_CLI_COMPARTMENT}" \
    --display-name "${KEY_NAME}" \
    --key-shape '{"algorithm":"AES","length":32}' \
    --protection-mode SOFTWARE \
    --freeform-tags "${FINOPS_TAGS}" \
    --query 'data')
  KEY_ID=$(jq -r '.id' <<<"${KEY_JSON}")
else
  KEY_ID=$(jq -r '.[0].id' <<<"${MATCHING_KEYS}")
fi

KEY_STATE=""
for attempt in {1..120}; do
  KEY_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" --endpoint "${MANAGEMENT_ENDPOINT}" \
    kms management key get \
    --key-id "${KEY_ID}" \
    --query 'data')
  KEY_STATE=$(jq -r '."lifecycle-state"' <<<"${KEY_JSON}")
  if [[ "${KEY_STATE}" == "ENABLED" ]]; then
    break
  fi
  if [[ "${KEY_STATE}" == "FAILED" || "${attempt}" -eq 120 ]]; then
    echo "ERRO: Chave '${KEY_NAME}' não atingiu ENABLED (estado: ${KEY_STATE})." >&2
    exit 1
  fi
  sleep 10
done

KEY_ALGORITHM=$(jq -r '."key-shape".algorithm' <<<"${KEY_JSON}")
KEY_LENGTH=$(jq -r '."key-shape".length' <<<"${KEY_JSON}")
KEY_PROTECTION_MODE=$(jq -r '."protection-mode"' <<<"${KEY_JSON}")
if [[ "${KEY_ALGORITHM}" != "AES" || "${KEY_LENGTH}" != "32" || "${KEY_PROTECTION_MODE}" != "SOFTWARE" ]]; then
  echo "ERRO: A chave existente '${KEY_NAME}' não corresponde a AES-256/SOFTWARE." >&2
  exit 1
fi
echo "Chave '${KEY_NAME}' habilitada (AES-256/SOFTWARE)."

SECRETS=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --vault-id "${VAULT_ID}" \
  --name "${SECRET_NAME}" \
  --all \
  --query 'data')
SECRET_ID=$(jq -r --arg name "${SECRET_NAME}" \
  '[.[] | select(."secret-name" == $name)][0].id // empty' <<<"${SECRETS}")

if [[ -z "${SECRET_ID}" ]]; then
  echo "Secret '${SECRET_NAME}' não encontrado. Criando..."
  GENERATED_PASSWORD="St@$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-18)9!"
  SECRET_CONTENT_BASE64=$(printf '%s' "${GENERATED_PASSWORD}" | base64 -w 0)
  SECRET_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret create-base64 \
    --compartment-id "${OCI_CLI_COMPARTMENT}" \
    --vault-id "${VAULT_ID}" \
    --key-id "${KEY_ID}" \
    --secret-name "${SECRET_NAME}" \
    --secret-content-content "${SECRET_CONTENT_BASE64}" \
    --secret-content-name initial \
    --secret-content-stage CURRENT \
    --freeform-tags "${FINOPS_TAGS}" \
    --query 'data')
  SECRET_ID=$(jq -r '.id' <<<"${SECRET_JSON}")
  unset GENERATED_PASSWORD SECRET_CONTENT_BASE64
else
  SECRET_COUNT=$(jq --arg name "${SECRET_NAME}" \
    '[.[] | select(."secret-name" == $name)] | length' <<<"${SECRETS}")
  if [[ "${SECRET_COUNT}" -gt 1 ]]; then
    echo "ERRO: Mais de um secret '${SECRET_NAME}' foi encontrado no Vault." >&2
    exit 1
  fi
fi

SECRET_STATE=""
for attempt in {1..120}; do
  SECRET_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret get \
    --secret-id "${SECRET_ID}" \
    --query 'data')
  SECRET_STATE=$(jq -r '."lifecycle-state"' <<<"${SECRET_JSON}")
  if [[ "${SECRET_STATE}" == "ACTIVE" ]]; then
    break
  fi
  if [[ "${SECRET_STATE}" == "FAILED" || "${SECRET_STATE}" == "DELETED" || "${attempt}" -eq 120 ]]; then
    echo "ERRO: Secret '${SECRET_NAME}' não atingiu ACTIVE (estado: ${SECRET_STATE})." >&2
    exit 1
  fi
  sleep 10
done

echo "Secret '${SECRET_NAME}' ativo."

OCIR_SECRETS=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --vault-id "${VAULT_ID}" \
  --name "${OCIR_SECRET_NAME}" \
  --all \
  --query 'data')
MATCHING_OCIR_SECRETS=$(jq -c --arg name "${OCIR_SECRET_NAME}" \
  '[.[] | select(."secret-name" == $name)]' <<<"${OCIR_SECRETS}")
OCIR_SECRET_COUNT=$(jq 'length' <<<"${MATCHING_OCIR_SECRETS}")

if [[ "${OCIR_SECRET_COUNT}" -gt 1 ]]; then
  echo "ERRO: Mais de um secret '${OCIR_SECRET_NAME}' foi encontrado no Vault." >&2
  exit 1
fi

if [[ "${OCIR_SECRET_COUNT}" -eq 0 ]]; then
  echo "Secret '${OCIR_SECRET_NAME}' não encontrado. Criando Auth Token do OCIR..."
  GENERATED_OCIR_TOKEN=$(oci --auth api_key --region "${OCI_CLI_REGION}" iam auth-token create \
    --user-id "${OCI_CLI_USER}" \
    --description "solidarytech-ocir-ci-token" \
    --query 'data.token' \
    --raw-output)
  if [[ -z "${GENERATED_OCIR_TOKEN}" || "${GENERATED_OCIR_TOKEN}" == "null" ]]; then
    echo "ERRO: OCI não retornou o Auth Token do OCIR." >&2
    exit 1
  fi

  OCIR_SECRET_CONTENT_BASE64=$(printf '%s' "${GENERATED_OCIR_TOKEN}" | base64 -w 0)
  OCIR_SECRET_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret create-base64 \
    --compartment-id "${OCI_CLI_COMPARTMENT}" \
    --vault-id "${VAULT_ID}" \
    --key-id "${KEY_ID}" \
    --secret-name "${OCIR_SECRET_NAME}" \
    --secret-content-content "${OCIR_SECRET_CONTENT_BASE64}" \
    --secret-content-name initial \
    --secret-content-stage CURRENT \
    --freeform-tags "${FINOPS_TAGS}" \
    --query 'data')
  OCIR_SECRET_ID=$(jq -r '.id' <<<"${OCIR_SECRET_JSON}")
  unset GENERATED_OCIR_TOKEN OCIR_SECRET_CONTENT_BASE64
else
  OCIR_SECRET_ID=$(jq -r '.[0].id' <<<"${MATCHING_OCIR_SECRETS}")
fi

OCIR_SECRET_STATE=""
for attempt in {1..120}; do
  OCIR_SECRET_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret get \
    --secret-id "${OCIR_SECRET_ID}" \
    --query 'data')
  OCIR_SECRET_STATE=$(jq -r '."lifecycle-state"' <<<"${OCIR_SECRET_JSON}")
  if [[ "${OCIR_SECRET_STATE}" == "ACTIVE" ]]; then
    break
  fi
  if [[ "${OCIR_SECRET_STATE}" == "FAILED" || "${OCIR_SECRET_STATE}" == "DELETED" || "${attempt}" -eq 120 ]]; then
    echo "ERRO: Secret '${OCIR_SECRET_NAME}' não atingiu ACTIVE (estado: ${OCIR_SECRET_STATE})." >&2
    exit 1
  fi
  sleep 10
done

echo "Secret '${OCIR_SECRET_NAME}' ativo."

ARGOCD_ADMIN_SECRETS=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret list \
  --compartment-id "${OCI_CLI_COMPARTMENT}" \
  --vault-id "${VAULT_ID}" \
  --name "${ARGOCD_ADMIN_SECRET_NAME}" \
  --all \
  --query 'data')
MATCHING_ARGOCD_ADMIN_SECRETS=$(jq -c --arg name "${ARGOCD_ADMIN_SECRET_NAME}" \
  '[.[] | select(."secret-name" == $name)]' <<<"${ARGOCD_ADMIN_SECRETS}")
ARGOCD_ADMIN_SECRET_COUNT=$(jq 'length' <<<"${MATCHING_ARGOCD_ADMIN_SECRETS}")

if [[ "${ARGOCD_ADMIN_SECRET_COUNT}" -gt 1 ]]; then
  echo "ERRO: Mais de um secret '${ARGOCD_ADMIN_SECRET_NAME}' foi encontrado no Vault." >&2
  exit 1
fi

if [[ "${ARGOCD_ADMIN_SECRET_COUNT}" -eq 0 ]]; then
  echo "Secret '${ARGOCD_ADMIN_SECRET_NAME}' não encontrado. Criando senha persistente..."
  GENERATED_ARGOCD_ADMIN_PASSWORD=$(openssl rand -base64 48 \
    | tr -dc 'A-Za-z0-9' \
    | cut -c1-20)
  if [[ "${#GENERATED_ARGOCD_ADMIN_PASSWORD}" -ne 20 ]]; then
    echo "ERRO: Não foi possível gerar uma senha alfanumérica de 20 caracteres." >&2
    exit 1
  fi

  ARGOCD_ADMIN_SECRET_CONTENT_BASE64=$(printf '%s' "${GENERATED_ARGOCD_ADMIN_PASSWORD}" | base64 -w 0)
  ARGOCD_ADMIN_SECRET_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret create-base64 \
    --compartment-id "${OCI_CLI_COMPARTMENT}" \
    --vault-id "${VAULT_ID}" \
    --key-id "${KEY_ID}" \
    --secret-name "${ARGOCD_ADMIN_SECRET_NAME}" \
    --secret-content-content "${ARGOCD_ADMIN_SECRET_CONTENT_BASE64}" \
    --secret-content-name initial \
    --secret-content-stage CURRENT \
    --freeform-tags "${FINOPS_TAGS}" \
    --query 'data')
  ARGOCD_ADMIN_SECRET_ID=$(jq -r '.id' <<<"${ARGOCD_ADMIN_SECRET_JSON}")
  unset GENERATED_ARGOCD_ADMIN_PASSWORD ARGOCD_ADMIN_SECRET_CONTENT_BASE64
else
  ARGOCD_ADMIN_SECRET_ID=$(jq -r '.[0].id' <<<"${MATCHING_ARGOCD_ADMIN_SECRETS}")
fi

ARGOCD_ADMIN_SECRET_STATE=""
for attempt in {1..120}; do
  ARGOCD_ADMIN_SECRET_JSON=$(oci --auth api_key --region "${OCI_CLI_REGION}" vault secret get \
    --secret-id "${ARGOCD_ADMIN_SECRET_ID}" \
    --query 'data')
  ARGOCD_ADMIN_SECRET_STATE=$(jq -r '."lifecycle-state"' <<<"${ARGOCD_ADMIN_SECRET_JSON}")
  if [[ "${ARGOCD_ADMIN_SECRET_STATE}" == "ACTIVE" ]]; then
    break
  fi
  if [[ "${ARGOCD_ADMIN_SECRET_STATE}" == "FAILED" ||
    "${ARGOCD_ADMIN_SECRET_STATE}" == "DELETED" ||
    "${attempt}" -eq 120 ]]; then
    echo "ERRO: Secret '${ARGOCD_ADMIN_SECRET_NAME}' não atingiu ACTIVE (estado: ${ARGOCD_ADMIN_SECRET_STATE})." >&2
    exit 1
  fi
  sleep 10
done

echo "Secret '${ARGOCD_ADMIN_SECRET_NAME}' ativo; valor preservado."

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "vault_id=${VAULT_ID}"
    echo "secret_id=${SECRET_ID}"
    echo "ocir_secret_id=${OCIR_SECRET_ID}"
  } >>"${GITHUB_OUTPUT}"
fi
