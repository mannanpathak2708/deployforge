# ============================================================================
#  outputs.tf — values exposed after `terraform apply`.
#
#  These are consumed by:
#    - Ansible (Stage 3): inventory.ini is generated from master_public_ip
#                         and worker_public_ips
#    - GitHub Actions (Stage 4): ECR URL is needed for `docker push`
#    - You: the kubectl / SSH commands print at the end of apply
# ============================================================================

output "master_public_ip" {
  description = "Public IP of the kubeadm master node — kubectl/SSH target"
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Private IP of the master, used for kubeadm advertise-address"
  value       = aws_instance.master.private_ip
}

output "master_public_dns" {
  description = "Public DNS of the master — useful for the Ingress host config"
  value       = aws_instance.master.public_dns
}

output "worker_public_ips" {
  description = "List of worker public IPs"
  value       = aws_instance.worker[*].public_ip
}

output "worker_private_ips" {
  description = "List of worker private IPs"
  value       = aws_instance.worker[*].private_ip
}

output "vpc_id" {
  description = "VPC ID (for Ansible network checks)"
  value       = aws_vpc.main.id
}

output "ecr_repository_url" {
  description = "ECR repo URL for `docker push` and the k8s deployment image field"
  value       = aws_ecr_repository.taskmanager.repository_url
}

output "ecr_registry" {
  description = "Just the registry portion (account.dkr.ecr.region.amazonaws.com)"
  value       = split("/", aws_ecr_repository.taskmanager.repository_url)[0]
}

output "aws_region" {
  description = "Echoed back so Ansible doesn't need to ask"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "Account ID (Stage 4 IAM policies need this)"
  value       = data.aws_caller_identity.current.account_id
}

# ----------------------------------------------------------------------------
#  Ready-to-paste SSH commands. Printed last so they're easy to find in the
#  apply output.
# ----------------------------------------------------------------------------

output "ssh_master" {
  description = "Copy-paste SSH command for the master"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.master.public_ip}"
}

output "ssh_workers" {
  description = "Copy-paste SSH commands for each worker"
  value = [
    for i, ip in aws_instance.worker[*].public_ip :
    "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}   # worker-${i + 1}"
  ]
}

# ----------------------------------------------------------------------------
#  Ansible inventory file content. Run this to write it to disk:
#    terraform output -raw ansible_inventory > ../ansible/inventory.ini
# ----------------------------------------------------------------------------

output "ansible_inventory" {
  description = "Auto-generated Ansible inventory — pipe into ../ansible/inventory.ini"
  value       = <<-EOT
    [master]
    ${aws_instance.master.public_ip} ansible_host=${aws_instance.master.public_ip} private_ip=${aws_instance.master.private_ip}

    [workers]
    %{for i, ip in aws_instance.worker[*].public_ip~}
    ${ip} ansible_host=${ip} private_ip=${aws_instance.worker[i].private_ip}
    %{endfor~}

    [k8s:children]
    master
    workers

    [k8s:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/${var.key_name}.pem
    ansible_python_interpreter=/usr/bin/python3
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
  EOT
}
