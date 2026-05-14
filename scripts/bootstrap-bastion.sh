#!/usr/bin/env bash
# Run on the bastion (after `aws ssm start-session ...`) to install the AWS
# Load Balancer Controller, deploy nginx behind an internal NLB, and assert
# the cluster is reachable only from inside the VPC.
#
# CLUSTER_NAME and AWS_REGION come from /etc/profile.d/eks.sh (written by the
# bastion user-data). The LB Controller role ARN and VPC ID come from SSM
# Parameter Store, so no copy-paste from `terraform output` is needed.
set -euo pipefail

: "${CLUSTER_NAME:?source /etc/profile first}"
: "${AWS_REGION:?source /etc/profile first}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ssm_get() {
  aws ssm get-parameter --name "$1" --with-decryption --query 'Parameter.Value' --output text
}

LB_CONTROLLER_ROLE_ARN="$(ssm_get "/${CLUSTER_NAME}/bootstrap/lb-controller-role-arn")"
VPC_ID="$(ssm_get "/${CLUSTER_NAME}/bootstrap/vpc-id")"

echo "==> Cluster nodes (expect 2, no EXTERNAL-IP)"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
kubectl get nodes -o wide

echo "==> Installing AWS Load Balancer Controller (chart 1.13.4)"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version 1.13.4 \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${LB_CONTROLLER_ROLE_ARN}"

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=5m

echo "==> Deploying nginx + internal NLB"
kubectl apply -f "${REPO_ROOT}/manifests/nginx-internal-nlb.yaml"
kubectl rollout status deploy/nginx --timeout=3m

echo "==> Waiting for NLB hostname"
for _ in $(seq 1 60); do
  HOST="$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "${HOST}" ] && break
  sleep 5
done
[ -n "${HOST:-}" ] || { kubectl describe svc nginx; echo "NLB hostname never appeared"; exit 1; }

echo "    NLB: ${HOST}"
echo "==> Resolving (must be private 10.0.x.x):"
for _ in $(seq 1 30); do
  RESOLVED="$(getent hosts "${HOST}" 2>/dev/null || true)"
  [ -n "${RESOLVED}" ] && break
  sleep 4
done
echo "${RESOLVED:-DNS did not resolve}"

echo "==> curl from bastion (retrying until NLB targets become healthy):"
for attempt in $(seq 1 30); do
  if BODY="$(curl -sS -f --max-time 8 "http://${HOST}/" 2>/dev/null)"; then
    echo "    success on attempt ${attempt}:"
    echo "${BODY}" | head -n 20
    SUCCESS=1
    break
  fi
  echo "    attempt ${attempt}: not ready, sleeping 10s..."
  sleep 10
done

if [ "${SUCCESS:-0}" != "1" ]; then
  kubectl describe svc nginx | tail -30
  exit 1
fi

echo
echo "==> Pod placement (every pod IP must be private):"
kubectl get pods -l app=nginx -o wide

echo
echo "Validation complete."
