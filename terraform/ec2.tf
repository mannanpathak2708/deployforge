# ============================================================================
#  ec2.tf — the actual machines.
#
#  Topology: 1 master + var.worker_count workers (default 2).
#
#  Each instance:
#    - Ubuntu 22.04 (looked up dynamically in main.tf)
#    - t3.medium (2 vCPU, 4 GB RAM)
#    - 30 GB gp3 root volume
#    - Public IP (we're in public subnets — see vpc.tf comment for why)
#    - Tagged with Role=master/worker so Ansible can target them
#    - cloud-init does the absolute minimum prep — full kubeadm setup is
#      handled by Ansible in Stage 3 (declarative config beats shell scripts).
#
#  Why two workers: kubeadm scheduling is more interesting with >1 worker and
#  rolling updates can actually demonstrate zero downtime. Single worker
#  works but is a less convincing demo.
# ============================================================================

# ----------------------------------------------------------------------------
#  cloud-init: minimal — just disable swap (kubeadm refuses to start otherwise)
#  and install qemu-guest-agent so AWS Console "Reboot/Stop" work cleanly.
# ----------------------------------------------------------------------------

locals {
  cloud_init_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # kubeadm requires swap off
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    # Hostname based on the Name tag will be set by Ansible later.
    # Set a temporary one based on private IP for now.
    PRIVATE_IP=$(hostname -I | awk '{print $1}' | tr '.' '-')
    hostnamectl set-hostname "deployforge-$${PRIVATE_IP}"

    apt-get update -y
    apt-get install -y python3 python3-apt   # ansible needs these
  EOF
}

# ----------------------------------------------------------------------------
#  Master node — single instance, gets the control-plane SG.
# ----------------------------------------------------------------------------

resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id   # first AZ
  vpc_security_group_ids      = [
    aws_security_group.ssh.id,
    aws_security_group.k8s_control_plane.id,
  ]
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ecr.name
  user_data                   = local.cloud_init_user_data
  user_data_replace_on_change = false   # don't recreate the instance on script edits

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens                 = "required"     # IMDSv2 only — defends against SSRF
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2              # so containers can read instance metadata
  }

  tags = {
    Name = "${var.project_name}-master"
    Role = "master"
  }

  # Ignore changes to AMI on apply — we don't want a new Ubuntu point release
  # to recreate the entire master and lose kubeadm state.
  lifecycle {
    ignore_changes = [ami]
  }
}

# ----------------------------------------------------------------------------
#  Worker nodes — N instances, distributed across AZs round-robin.
# ----------------------------------------------------------------------------

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids      = [
    aws_security_group.ssh.id,
    aws_security_group.k8s_worker.id,
  ]
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ecr.name
  user_data                   = local.cloud_init_user_data
  user_data_replace_on_change = false

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Role = "worker"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
