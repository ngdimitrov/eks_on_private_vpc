#!/bin/bash
# shellcheck disable=SC2034,SC2154
# cluster_name and region come from terraform templatefile().
set -euxo pipefail

CLUSTER_NAME="${cluster_name}"
REGION="${region}"

# NAT GW data plane can lag behind Terraform "complete" by ~1 min on fresh apply.
for i in $(seq 1 60); do
  curl -fsS -o /dev/null --max-time 5 https://aws.amazon.com && break
  echo "waiting for NAT egress... ($i)"
  sleep 5
done

# AL2023 ships curl-minimal; installing the full curl package conflicts.
dnf install -y --quiet tar gzip bash-completion jq

# kubectl pinned + integrity-verified against the official published checksum.
KUBECTL_VERSION="v1.35.5"
curl -fsSL --retry 5 --retry-delay 6 -o /tmp/kubectl \
  "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -fsSL --retry 5 --retry-delay 6 -o /tmp/kubectl.sha256 \
  "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum -c -
install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl /tmp/kubectl.sha256

# Helm: pin both the installer script (tagged ref, not mutable main) and the
# helm version. get-helm-3 verifies the release tarball checksum itself.
HELM_VERSION="v3.16.3"
curl -fsSL --retry 5 --retry-delay 6 \
  "https://raw.githubusercontent.com/helm/helm/$${HELM_VERSION}/scripts/get-helm-3" \
  | DESIRED_VERSION="$${HELM_VERSION}" HELM_INSTALL_DIR=/usr/local/bin USE_SUDO=false bash

cat > /etc/profile.d/eks.sh <<EOF
export AWS_REGION=$${REGION}
export AWS_DEFAULT_REGION=$${REGION}
export CLUSTER_NAME=$${CLUSTER_NAME}
export KUBECONFIG=/home/ec2-user/.kube/config
EOF
chmod 0644 /etc/profile.d/eks.sh

# IMDS credentials and the EKS access-entry rollout can race on first boot.
mkdir -p /home/ec2-user/.kube
for i in $(seq 1 12); do
  aws eks update-kubeconfig \
    --name "$${CLUSTER_NAME}" --region "$${REGION}" \
    --kubeconfig /home/ec2-user/.kube/config && break
  echo "kubeconfig attempt $i failed, retrying..."
  sleep 10
done
chown -R ec2-user:ec2-user /home/ec2-user/.kube

echo 'source <(kubectl completion bash)' >> /home/ec2-user/.bashrc
echo 'alias k=kubectl' >> /home/ec2-user/.bashrc
chown ec2-user:ec2-user /home/ec2-user/.bashrc
