#!/usr/bin/env bash
# Idempotent: creates the S3 bucket that holds the Terraform state with a
# customer-managed KMS key (SSE-KMS), versioning, TLS-only access, and
# block-public-access, then writes terraform/backend.hcl so that
# `terraform init -backend-config=backend.hcl` wires up the remote backend
# without anyone editing a tracked file.
#
# Bucket name = <prefix>-tfstate-<account_id>, region defaults to eu-west-1.
# Override via env: BUCKET_PREFIX=foo REGION=eu-central-1 ./bootstrap-state-bucket.sh
set -euo pipefail

REGION="${REGION:-eu-west-1}"
BUCKET_PREFIX="${BUCKET_PREFIX:-eks-private-demo}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${BUCKET_PREFIX}-tfstate-${ACCOUNT}"
KEY_ALIAS="alias/${BUCKET_PREFIX}-tfstate"
HCL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/terraform/backend.hcl"

echo "==> Account ${ACCOUNT}, region ${REGION}, bucket ${BUCKET}"

if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "    bucket already exists, reusing"
else
  echo "==> Creating bucket"
  aws s3api create-bucket \
    --bucket "${BUCKET}" --region "${REGION}" \
    --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
fi

echo "==> Resolving state KMS key (${KEY_ALIAS})"
if KEY_ARN="$(aws kms describe-key --key-id "${KEY_ALIAS}" --region "${REGION}" \
  --query 'KeyMetadata.Arn' --output text 2>/dev/null)"; then
  echo "    key already exists, reusing"
else
  echo "==> Creating customer-managed KMS key"
  KEY_ID="$(aws kms create-key --region "${REGION}" \
    --description "Terraform state encryption (${BUCKET})" \
    --tags TagKey=ManagedBy,TagValue=bootstrap-script \
    --query 'KeyMetadata.KeyId' --output text)"
  aws kms enable-key-rotation --key-id "${KEY_ID}" --region "${REGION}"
  aws kms create-alias --alias-name "${KEY_ALIAS}" \
    --target-key-id "${KEY_ID}" --region "${REGION}"
  KEY_ARN="$(aws kms describe-key --key-id "${KEY_ID}" --region "${REGION}" \
    --query 'KeyMetadata.Arn' --output text)"
fi

echo "==> Enabling versioning"
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "==> Enabling default encryption (SSE-KMS, customer-managed key)"
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration "{
    \"Rules\": [{
      \"ApplyServerSideEncryptionByDefault\": {
        \"SSEAlgorithm\": \"aws:kms\",
        \"KMSMasterKeyID\": \"${KEY_ARN}\"
      },
      \"BucketKeyEnabled\": true
    }]
  }"

echo "==> Blocking all public access"
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> Enforcing TLS-only access (deny aws:SecureTransport=false)"
aws s3api put-bucket-policy --bucket "${BUCKET}" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"DenyInsecureTransport\",
    \"Effect\": \"Deny\",
    \"Principal\": \"*\",
    \"Action\": \"s3:*\",
    \"Resource\": [
      \"arn:aws:s3:::${BUCKET}\",
      \"arn:aws:s3:::${BUCKET}/*\"
    ],
    \"Condition\": { \"Bool\": { \"aws:SecureTransport\": \"false\" } }
  }]
}"

echo "==> Writing ${HCL}"
cat > "${HCL}" <<EOF
bucket = "${BUCKET}"
EOF

echo
echo "Done. Initialize the backend with:"
echo "  terraform -chdir=terraform init -backend-config=backend.hcl"
