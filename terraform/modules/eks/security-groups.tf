locals {
  cluster_primary_sg_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# Do NOT tag this SG with kubernetes.io/cluster/<name> — the cluster primary SG
# already has it, and AWS LB Controller v2.13+ refuses ENIs with more than one
# tagged SG ("expected exactly one securityGroup tagged with ...").
resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node"
  description = "Worker node SG for ${var.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.cluster_name}-node" })
}

resource "aws_vpc_security_group_ingress_rule" "node_self_all" {
  security_group_id            = aws_security_group.node.id
  description                  = "All traffic between nodes"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.node.id
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cp_kubelet" {
  security_group_id            = aws_security_group.node.id
  description                  = "kubelet/ephemeral from control plane"
  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535
  referenced_security_group_id = local.cluster_primary_sg_id
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cp_tls" {
  security_group_id            = aws_security_group.node.id
  description                  = "TLS from control plane to pods on :443"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = local.cluster_primary_sg_id
}

# Scoped egress instead of all-protocol 0.0.0.0/0: 443 to the internet covers
# image pulls (public.ecr.aws) and any AWS API not served by a VPC endpoint;
# everything else (pod/pod, node/control-plane, DNS, kubelet) stays in-VPC.
# By design: nodes reach AWS APIs and public image registries (public.ecr.aws)
# over HTTPS via NAT; those have no stable, narrow CIDR. Locked to tcp/443.
# Documented exception (mirrors README).
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "node_https" {
  security_group_id = aws_security_group.node.id
  description       = "HTTPS to AWS APIs / image registries via NAT + VPC endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "node_vpc_all" {
  security_group_id = aws_security_group.node.id
  description       = "All traffic within the VPC (pods, control plane, DNS, kubelet)"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr_block
}
