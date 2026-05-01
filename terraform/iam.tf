# ============================================================================
#  iam.tf — IAM role for EC2 → ECR pull access.
#
#  Without this, kubelet would fail to pull images from ECR with a 401.
#  We attach AmazonEC2ContainerRegistryReadOnly via an instance profile to
#  every cluster node. This avoids hardcoding AWS credentials in
#  ~/.docker/config.json on the EC2s.
# ============================================================================

resource "aws_iam_role" "ec2_ecr" {
  name = "${var.project_name}-ec2-ecr-role"

  # Trust policy: EC2 service can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-ec2-ecr-role"
  }
}

# ECR ReadOnly is sufficient — we never push from inside the cluster, only pull.
# Pushes happen from GitHub Actions in Stage 4 using a separate IAM user.
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# CloudWatch agent permissions — useful for debugging kubelet logs from outside
# the cluster. Optional but recommended; costs are negligible for short demos.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance profile is the wrapper EC2 actually uses to attach a role to an
# instance. Easy to forget — without it, the EC2 has the policy attached to a
# role that nothing assumes.
resource "aws_iam_instance_profile" "ec2_ecr" {
  name = "${var.project_name}-ec2-ecr-profile"
  role = aws_iam_role.ec2_ecr.name
}
