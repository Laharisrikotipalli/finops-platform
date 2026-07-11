# terraform/node_pools.tf
# Node groups are defined directly inside main.tf's eks module block.
# This file only holds shared locals used elsewhere.

locals {
  common_labels = {
    "cluster"     = var.cluster_name
    "environment" = var.environment
    "managed-by"  = "terraform"
  }
}
