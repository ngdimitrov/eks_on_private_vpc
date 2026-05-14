#!/usr/bin/env bash
# Idempotent: creates the S3 bucket that holds the Terraform state, enables
# versioning, encryption, and block-public-access, then writes
# terraform/backend.hcl so that `terraform init -backend-config=backend.hcl`
# wires up the remote backend without anyone editing a tracked file.
#
# Bucket name = <prefix>-tfstate-<account_id>, region defaults to eu-west-1.
# Override via env: BUCKET_PREFIX=foo REGION=eu-central-1 ./bootstrap-state-bucket.sh
set -euo pipefail

REGION="${REGION:-eu-west-1}"
BUCKET_PREFIX="${BUCKET_PREFIX:-eks-private-demo}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${BUCKET_PREFIX}-tfstate-${ACCOUNT}"
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

echo "==> Enabling versioning"
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "==> Enabling default encryption (AES256)"
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

echo "==> Blocking all public access"
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> Writing ${HCL}"
cat > "${HCL}" <<EOF
bucket = "${BUCKET}"
EOF

echo
echo "Done. Initialize the backend with:"
echo "  terraform -chdir=terraform init -backend-config=backend.hcl"
