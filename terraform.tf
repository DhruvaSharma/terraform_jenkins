terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20.0"
    }
  }

  required_version = ">= 1.2.0"
}

data "aws_availability_zones" "available" {}

# Set AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "eks_vpc"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnet" {
  count      = 2
  cidr_block = "10.0.${count.index + 1}.0/24"
  vpc_id     = aws_vpc.eks_vpc.id
  #availability_zone = "us-east-1${count.index + 1}"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

# Create security group for EKS control plane
resource "aws_security_group" "eks_control_plane_sg" {
  name_prefix = "eks-control-plane-sg"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  tags = {
    Name = "eks-control-plane-sg"
  }
}

# Create IAM roles for EKS
resource "aws_iam_role" "eks_cluster_role" {
  name_prefix = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_service" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_cluster_role.name
}

# Create EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "eks_cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.21"
  vpc_config {
    subnet_ids              = aws_subnet.private_subnet.*.id
    endpoint_private_access = true
  }
  depends_on = [
    aws_security_group.eks_control_plane_sg
  ]
  tags = {
    Name = "eks_cluster"
  }
}

# Create EKS Managed Node Group
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks_node_group"
  node_role_arn   = aws_iam_role.eks_cluster_role.arn
  subnet_ids      = aws_subnet.private_subnet.*.id
  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
  depends_on = [
    aws_eks_cluster.eks_cluster,
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_service,
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.ecr_readonly
  ]
  tags = {
    Name = "eks_node_group"
  }
}

# Create EC2 instance
resource "aws_instance" "eks_ec2" {
  ami                    = "ami-007855ac798b5175e" # Ubuntu Server 22.04 LTS
  instance_type          = "t2.micro"
  key_name               = "terraform_eks"
  vpc_security_group_ids = [aws_security_group.eks_control_plane_sg.id]
  subnet_id              = aws_subnet.private_subnet[0].id
  #   subnet_id = flatten([
  #     aws_subnet.private_subnet.*.id
  #   ])
  #   subnet_id = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "eks_ec2"
  }
}

# # Create AWS Load Balancer Controller
# resource "kubectl_manifest" "aws_load_balancer_controller" {
#   manifest = templatefile("${path.root}/k8s/aws_load_balancer_controller.yaml", {
#     cluster_name = aws_eks_cluster.eks_cluster.name,
#   })
#   depends_on = [
#     aws_eks_cluster.eks_cluster,
#   ]
#   tags = {
#     Name = "aws-load-balancer-controller"
#   }
# }
