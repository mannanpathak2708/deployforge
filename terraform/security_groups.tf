# ============================================================================
#  security_groups.tf — kubeadm port requirements baked into SGs.
#
#  Reference: https://kubernetes.io/docs/reference/networking/ports-and-protocols/
#
#  Three SGs:
#    1. ssh                — port 22 from your laptop only
#    2. k8s_control_plane  — control plane ports (master only)
#    3. k8s_worker         — worker ports (kubelet, NodePort range)
#
#  The master gets BOTH ssh + control_plane. Workers get ssh + worker.
#  All cluster nodes also need to talk to each other freely on the pod/service
#  network — handled by self-referencing rules.
# ============================================================================

# ----------------------------------------------------------------------------
#  1. SSH access — locked to your IP
# ----------------------------------------------------------------------------

resource "aws_security_group" "ssh" {
  name        = "${var.project_name}-ssh"
  description = "Allow SSH from operator IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat([var.my_public_ip], var.additional_ssh_cidrs)
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ssh"
  }
}

# ----------------------------------------------------------------------------
#  2. Control-plane (master) security group
#     Ports per kubeadm docs:
#       6443       — kube-apiserver (HTTPS)
#       2379-2380  — etcd server client API
#       10250      — kubelet API
#       10257      — kube-controller-manager
#       10259      — kube-scheduler
#       30000-32767 — NodePort services (master can also serve them)
# ----------------------------------------------------------------------------

resource "aws_security_group" "k8s_control_plane" {
  name        = "${var.project_name}-k8s-control-plane"
  description = "kubeadm control-plane required ports"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "kube-apiserver — accessed by kubectl from operator + workers"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = concat([var.my_public_ip], var.additional_ssh_cidrs, [var.vpc_cidr])
  }

  ingress {
    description = "etcd client/peer — internal only"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "kubelet API — workers and master"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "kube-controller-manager + kube-scheduler"
    from_port   = 10257
    to_port     = 10259
    protocol    = "tcp"
    self        = true
  }

  # NodePort services — used by kube-prometheus-stack and the app's ingress
  ingress {
    description = "NodePort range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = concat([var.my_public_ip], [var.vpc_cidr])
  }

  # Allow all pod-to-pod traffic between cluster nodes. Calico CNI handles
  # NetworkPolicy enforcement at the pod level inside Kubernetes; the SG just
  # needs to not get in the way of the underlying VXLAN/IP-in-IP traffic.
  ingress {
    description = "All traffic from cluster nodes (CNI overlay)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-k8s-control-plane"
  }
}

# ----------------------------------------------------------------------------
#  3. Worker security group
#     Ports:
#       10250        — kubelet API (master scrapes this)
#       30000-32767  — NodePort range
#       Calico needs IP-in-IP (protocol 4) or VXLAN (UDP 4789) between nodes
# ----------------------------------------------------------------------------

resource "aws_security_group" "k8s_worker" {
  name        = "${var.project_name}-k8s-worker"
  description = "kubeadm worker required ports"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "NodePort range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = concat([var.my_public_ip], [var.vpc_cidr])
  }

  ingress {
    description = "All inter-node traffic (CNI overlay)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-k8s-worker"
  }
}

# ----------------------------------------------------------------------------
#  Cross-SG rule: master needs to reach worker kubelets and vice versa.
#  Defining this as a standalone rule (not inline) avoids circular dependency
#  errors that can crop up if both SGs reference each other in their resource
#  blocks.
# ----------------------------------------------------------------------------

resource "aws_security_group_rule" "control_plane_to_worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.k8s_control_plane.id
  security_group_id        = aws_security_group.k8s_worker.id
  description              = "Master → workers (all ports)"
}

resource "aws_security_group_rule" "worker_to_control_plane" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.k8s_worker.id
  security_group_id        = aws_security_group.k8s_control_plane.id
  description              = "Workers → master (all ports)"
}
