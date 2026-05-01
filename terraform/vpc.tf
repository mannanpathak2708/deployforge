# ============================================================================
#  vpc.tf — networking foundation.
#
#  Layout:
#    VPC 10.0.0.0/16
#      ├── Public subnet A (10.0.1.0/24) in us-east-1a
#      └── Public subnet B (10.0.2.0/24) in us-east-1b
#      └── Internet Gateway → Route Table (0.0.0.0/0 → IGW)
#
#  Why public subnets only: this is a course project on a tight budget. A
#  proper production setup would put workers in private subnets with a NAT
#  Gateway, but NAT is ~$32/month even when idle. Public subnets + tight
#  security groups are an acceptable trade for a one-week demo.
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true   # so EC2s get DNS names like ip-10-0-1-23.ec2.internal
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true   # auto-assigns public IPs to instances launched here

  tags = {
    Name                                            = "${var.project_name}-public-${var.availability_zones[count.index]}"
    # These tags are read by the AWS cloud-controller-manager when k8s creates
    # LoadBalancer-type services. They're not strictly needed for self-managed
    # kubeadm without the AWS CCM, but harmless to include.
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.project_name}-k8s" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
