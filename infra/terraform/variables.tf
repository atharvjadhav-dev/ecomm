variable "aws_region" {
  description = "AWS region to deploy all resources into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = "medusa-ecomm"
}

variable "environment" {
  description = "Deployment environment label (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "domain_name" {
  description = "Public domain name managed in Hostinger (e.g., ecom.example.com). Leave empty to skip ACM creation."
  type        = string
  default     = "ecom.example.com"
}

variable "enable_https" {
  description = "Enable the ALB HTTPS (443) listener and HTTP-to-HTTPS redirect. Set to false until the Hostinger ACM validation CNAME is verified and the certificate status is ISSUED."
  type        = bool
  default     = false
}

variable "existing_acm_certificate_arn" {
  description = "Optional ARN of an already-issued ACM certificate. If empty and domain_name is set, Terraform creates a DNS-validated ACM certificate."
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository in 'owner/repo' format allowed to assume the OIDC deployment role"
  type        = string
  default     = "your-github-org/your-repo"
}

variable "github_branch" {
  description = "Git branch allowed to assume the GitHub Actions OIDC deployment role"
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "Whether to create the IAM OIDC provider for token.actions.githubusercontent.com (set to false if one already exists in the AWS account)"
  type        = bool
  default     = true
}

variable "backend_desired_count" {
  description = "Desired number of Fargate tasks for the Medusa backend (Requirement: 1 initially)"
  type        = number
  default     = 1
}

variable "storefront_desired_count" {
  description = "Desired number of Fargate tasks for the Next.js storefront (Requirement: 1 initially)"
  type        = number
  default     = 1
}

variable "backend_cpu" {
  description = "Fargate CPU units for the Medusa backend task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "backend_memory" {
  description = "Fargate memory (MiB) for the Medusa backend task"
  type        = number
  default     = 2048
}

variable "storefront_cpu" {
  description = "Fargate CPU units for the Next.js storefront task (512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "storefront_memory" {
  description = "Fargate memory (MiB) for the Next.js storefront task"
  type        = number
  default     = 1024
}

variable "backend_image_tag" {
  description = "Initial Docker image tag for the Medusa backend in ECR"
  type        = string
  default     = "latest"
}

variable "storefront_image_tag" {
  description = "Initial Docker image tag for the Next.js storefront in ECR"
  type        = string
  default     = "latest"
}

variable "db_instance_class" {
  description = "Amazon RDS PostgreSQL instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GiB for RDS PostgreSQL"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Database name created inside RDS PostgreSQL"
  type        = string
  default     = "medusa_db"
}

variable "db_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  default     = "medusa_admin"
}

variable "redis_node_type" {
  description = "Amazon ElastiCache Redis node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "storefront_publishable_key" {
  description = "Medusa publishable API key token synced into PostgreSQL by initial-data-seed.ts and passed to the storefront"
  type        = string
  sensitive   = true
  default     = "pk_replace_with_medusa_publishable_key"
}

variable "default_region_code" {
  description = "Default country/region code for the Next.js storefront"
  type        = string
  default     = "dk"
}

variable "admin_email" {
  description = "Initial Medusa admin user email stored in AWS Secrets Manager"
  type        = string
  default     = "admin@example.com"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 14
}
