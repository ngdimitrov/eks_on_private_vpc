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

curl -fsSL --retry 5 --retry-delay 6 -o /usr/local/bin/kubectl \
  https://dl.k8s.io/release/v1.31.4/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl

curl -fsSL --retry 5 --retry-delay 6 https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
  | HELM_INSTALL_DIR=/usr/local/bin USE_SUDO=false bash

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
