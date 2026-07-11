# terraform/iam.tf
# IAM roles for Kubecost billing access and Cluster Autoscaler.
# Uses IRSA (IAM Roles for Service Accounts) – no static credentials.

# ── Kubecost billing assume-role policy ───────────────────────────────────
data "aws_iam_policy_document" "kubecost_billing_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.kubecost_namespace}:kubecost-cost-analyzer"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kubecost_billing_role" {
  name               = "${var.cluster_name}-kubecost-billing"
  assume_role_policy = data.aws_iam_policy_document.kubecost_billing_assume_role.json

  tags = {
    Name      = "${var.cluster_name}-kubecost-billing"
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "kubecost_billing_policy" {
  statement {
    sid    = "CURBucketListAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = ["arn:aws:s3:::${var.cost_report_s3_bucket}"]
  }

  statement {
    sid    = "CURObjectReadAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["arn:aws:s3:::${var.cost_report_s3_bucket}/*"]
  }

  statement {
    sid    = "CostExplorerReadOnly"
    effect = "Allow"
    actions = [
      "ce:GetCostAndUsage",
      "ce:GetCostForecast",
      "ce:GetDimensionValues",
      "ce:GetRightsizingRecommendation",
      "ce:GetUsageForecast",
      "ce:ListCostAllocationTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EC2PricingReadOnly"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeRegions",
      "ec2:DescribeSpotPriceHistory",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "kubecost_billing_policy" {
  name        = "${var.cluster_name}-kubecost-billing-policy"
  description = "Least-privilege billing read access for Kubecost"
  policy      = data.aws_iam_policy_document.kubecost_billing_policy.json
}

resource "aws_iam_role_policy_attachment" "kubecost_billing" {
  role       = aws_iam_role.kubecost_billing_role.name
  policy_arn = aws_iam_policy.kubecost_billing_policy.arn
}

# ── Cluster Autoscaler role ────────────────────────────────────────────────
data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler_role" {
  name               = "${var.cluster_name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role.json

  tags = {
    Name      = "${var.cluster_name}-cluster-autoscaler"
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "cluster_autoscaler_policy" {
  statement {
    sid    = "AutoScalingDescribe"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AutoScalingModify"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler_policy" {
  name        = "${var.cluster_name}-cluster-autoscaler-policy"
  description = "Cluster Autoscaler ASG permissions"
  policy      = data.aws_iam_policy_document.cluster_autoscaler_policy.json
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler_role.name
  policy_arn = aws_iam_policy.cluster_autoscaler_policy.arn
}

# ── S3 bucket for Cost & Usage Reports ────────────────────────────────────
resource "aws_s3_bucket" "cur_bucket" {
  bucket        = var.cost_report_s3_bucket
  force_destroy = true

  tags = {
    Name      = var.cost_report_s3_bucket
    Purpose   = "AWS Cost and Usage Reports for Kubecost"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "cur_bucket" {
  bucket = aws_s3_bucket.cur_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur_bucket" {
  bucket = aws_s3_bucket.cur_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cur_bucket" {
  bucket                  = aws_s3_bucket.cur_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "cur_bucket_policy" {
  statement {
    sid    = "AllowBillingRead"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl", "s3:GetBucketPolicy"]
    resources = [aws_s3_bucket.cur_bucket.arn]
  }
  statement {
    sid    = "AllowBillingPut"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cur_bucket.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "cur_bucket" {
  bucket = aws_s3_bucket.cur_bucket.id
  policy = data.aws_iam_policy_document.cur_bucket_policy.json
}

# ── Outputs ───────────────────────────────────────────────────────────────
output "kubecost_iam_role_arn" {
  description = "IAM role ARN for Kubecost billing access"
  value       = aws_iam_role.kubecost_billing_role.arn
}

output "cluster_autoscaler_iam_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler_role.arn
}