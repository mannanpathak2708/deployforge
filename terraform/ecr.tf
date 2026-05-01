# ============================================================================
#  ecr.tf — Elastic Container Registry for the Docker image.
#
#  GitHub Actions (Stage 4) pushes here on every commit to main; the cluster
#  pulls from here via the IAM role attached in iam.tf.
#
#  A lifecycle policy keeps the last 10 images and expires older ones — ECR
#  charges $0.10/GB-month for storage, and untagged old images add up fast.
# ============================================================================

resource "aws_ecr_repository" "taskmanager" {
  name                 = "${var.project_name}/taskmanager"
  image_tag_mutability = "MUTABLE"   # MUTABLE allows overwriting :latest. IMMUTABLE for prod.

  # Trivy scans the image during the CI pipeline already; this is belt-and-braces.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt at rest using AWS-managed KMS key (free).
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-taskmanager"
  }
}

resource "aws_ecr_lifecycle_policy" "taskmanager" {
  repository = aws_ecr_repository.taskmanager.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPatternList = ["v*", "main-*", "sha-*"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
