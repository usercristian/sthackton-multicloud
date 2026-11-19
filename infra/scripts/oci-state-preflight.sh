#!/usr/bin/env bash
set -euo pipefail

: "${OCI_CLI_COMPARTMENT:?Variável OCI_CLI_COMPARTMENT não definida}"
: "${OCI_CLI_REGION:=sa-saopaulo-1}"
: "${TF_STATE_BUCKET:=solidarytech-tfstate-prod}"

echo "Iniciando preflight do backend Terraform na OCI (região: ${OCI_CLI_REGION})..."

# 1. Obtém o namespace do Object Storage da Tenancy
NAMESPACE=$(oci os ns get --auth api_key --query 'data' --raw-output)
if [[ -z "${NAMESPACE}" ]]; then
  echo "ERRO: Não foi possível obter o namespace do Object Storage."
  exit 1
fi
echo "Namespace identificado: ${NAMESPACE}"

# 2. Verifica se o bucket determinístico já existe
set +e
BUCKET_JSON=$(oci os bucket get \
  --auth api_key \
  --namespace-name "${NAMESPACE}" \
  --bucket-name "${TF_STATE_BUCKET}" \
  --query 'data' 2>/dev/null)
GET_EXIT_CODE=$?
set -e

if [[ ${GET_EXIT_CODE} -ne 0 || -z "${BUCKET_JSON}" ]]; then
  echo "Bucket '${TF_STATE_BUCKET}' não encontrado. Criando com políticas de segurança e FinOps..."

  oci os bucket create \
    --auth api_key \
    --compartment-id "${OCI_CLI_COMPARTMENT}" \
    --namespace-name "${NAMESPACE}" \
    --name "${TF_STATE_BUCKET}" \
    --public-access-type "NoPublicAccess" \
    --versioning "Enabled" \
    --storage-tier "Standard" \
    --freeform-tags '{"Project":"Solidary Tech","Environment":"Production","CostCenter":"NGO-Core","ManagedBy":"CI-Preflight"}' \
    >/dev/null

  echo "Bucket '${TF_STATE_BUCKET}' criado com sucesso."
else
  echo "Bucket '${TF_STATE_BUCKET}' encontrado. Validando conformidade..."

  BUCKET_COMPARTMENT=$(echo "${BUCKET_JSON}" | jq -r '."compartment-id"')
  PUBLIC_ACCESS=$(echo "${BUCKET_JSON}" | jq -r '."public-access-type"')
  VERSIONING=$(echo "${BUCKET_JSON}" | jq -r '.versioning')

  if [[ "${BUCKET_COMPARTMENT}" != "${OCI_CLI_COMPARTMENT}" ]]; then
    echo "ERRO DE SEGURANÇA: O bucket '${TF_STATE_BUCKET}' pertence a outro compartment (${BUCKET_COMPARTMENT})."
    exit 1
  fi

  if [[ "${PUBLIC_ACCESS}" != "NoPublicAccess" ]]; then
    echo "ERRO DE SEGURANÇA: O bucket '${TF_STATE_BUCKET}' não está privado (${PUBLIC_ACCESS})."
    exit 1
  fi

  if [[ "${VERSIONING}" != "Enabled" ]]; then
    echo "ERRO DE GOVERNANÇA: O bucket '${TF_STATE_BUCKET}' está sem versionamento habilitado (${VERSIONING})."
    exit 1
  fi

  echo "Conformidade validada: compartment correto, acesso privado e versionamento ativo."
fi

# 3. Exporta outputs para os próximos steps do GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "namespace=${NAMESPACE}" >> "${GITHUB_OUTPUT}"
  echo "bucket=${TF_STATE_BUCKET}" >> "${GITHUB_OUTPUT}"
  echo "region=${OCI_CLI_REGION}" >> "${GITHUB_OUTPUT}"
fi