# ============================================================
# terraform/main.tf
# FinOps Platform – EKS Cluster (AWS)
# Fix: removed aws-ebs-csi-driver from cluster_addons to avoid
#      20-minute timeout. Install it via Helm post-cluster-creation.
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }

  # Remote state – create the S3 bucket and DynamoDB table once manually,
  # then uncomment this block. Comment it out for first-time local runs.
  # backend "s3" {
  #   bucket         = "finops-platform-tfstate"
  #   key            = "global/eks/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "finops-platform-tf-lock"
  # }
}

# ── Providers ─────────────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.cluster_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = true   # single NAT saves cost for dev/staging
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for EKS load balancer controller
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # OIDC provider for IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Grant cluster creator admin access
  enable_cluster_creator_admin_permissions = true

  # ── Core addons only ──────────────────────────────────────────────────────
  # NOTE: aws-ebs-csi-driver is intentionally excluded here.
  # It requires a dedicated IAM role and consistently times out (>20 min)
  # when provisioned via Terraform addon during node group creation.
  # Install it separately with Helm after the cluster is ready:
  #   helm upgrade --install aws-ebs-csi-driver \
  #     aws-ebs-csi-driver/aws-ebs-csi-driver --namespace kube-system
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
  }

  # ── Node groups (on-demand + spot) ────────────────────────────────────────
  eks_managed_node_groups = {

    # Stable pool for system components: Kubecost, Prometheus, Grafana, CA
    on_demand_base = {
      name           = "on-demand-base"
      capacity_type  = "ON_DEMAND"
      instance_types = [var.on_demand_instance_type]

      min_size     = var.on_demand_min_size
      max_size     = var.on_demand_max_size
      desired_size = var.on_demand_desired_size

      ami_type  = "AL2023_x86_64_STANDARD"
      disk_size = 50

      labels = {
        lifecycle = "on-demand"
        intent    = "system"
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"                       = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}"           = "owned"
        "k8s.io/cluster-autoscaler/node-template/label/lifecycle" = "on-demand"
      }
    }

    # Cost-optimised pool for application workloads
    spot_workloads = {
      name           = "spot-workloads"
      capacity_type  = "SPOT"
      instance_types = var.spot_instance_types

      min_size     = var.spot_min_size
      max_size     = var.spot_max_size
      desired_size = var.spot_desired_size

      ami_type  = "AL2023_x86_64_STANDARD"
      disk_size = 50

      labels = {
        lifecycle = "spot"
        intent    = "apps"
      }

      # Taint so only tolerant pods schedule here
      taints = {
        spot_instance = {
          key    = "spotInstance"
          value  = "true"
          effect = "PREFER_NO_SCHEDULE"
        }
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"                          = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}"              = "owned"
        "k8s.io/cluster-autoscaler/node-template/label/lifecycle"    = "spot"
        "k8s.io/cluster-autoscaler/node-template/taint/spotInstance" = "true:PREFER_NO_SCHEDULE"
      }
    }
  }

  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}