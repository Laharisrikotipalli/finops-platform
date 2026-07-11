variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "finops-platform"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "environment" {
  description = "Deployment environment (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to deploy resources into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "on_demand_instance_type" {
  description = "EC2 instance type for on-demand node group"
  type        = string
  default     = "t3.medium"
}

variable "spot_instance_types" {
  description = "List of EC2 instance types for spot node group (multiple types reduce interruption)"
  type        = list(string)
  default     = ["t3.large", "m5.large", "c5.large", "m4.large", "c4.large"]
}

variable "on_demand_min_size" {
  description = "Minimum number of nodes in the on-demand node group"
  type        = number
  default     = 2
}

variable "on_demand_max_size" {
  description = "Maximum number of nodes in the on-demand node group"
  type        = number
  default     = 5
}

variable "on_demand_desired_size" {
  description = "Desired number of nodes in the on-demand node group"
  type        = number
  default     = 2
}

variable "spot_min_size" {
  description = "Minimum number of nodes in the spot node group"
  type        = number
  default     = 1
}

variable "spot_max_size" {
  description = "Maximum number of nodes in the spot node group"
  type        = number
  default     = 20
}

variable "spot_desired_size" {
  description = "Desired number of nodes in the spot node group"
  type        = number
  default     = 2
}

variable "kubecost_token" {
  description = "Kubecost product key/token (free tier available)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_account_id" {
  description = "AWS Account ID for IAM role ARN construction"
  type        = string
}

variable "cost_report_s3_bucket" {
  description = "S3 bucket name where AWS Cost and Usage Reports are stored"
  type        = string
  default     = "finops-platform-cur-reports"
}

variable "kubecost_namespace" {
  description = "Kubernetes namespace for Kubecost deployment"
  type        = string
  default     = "kubecost"
}

variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring stack (Prometheus/Grafana)"
  type        = string
  default     = "monitoring"
}