output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer (set this as the CNAME target in Hostinger)"
  value       = aws_lb.main.dns_name
}

output "alb_http_url" {
  description = "Direct HTTP URL of the Application Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "domain_url" {
  description = "Custom domain URL configured for Hostinger"
  value       = var.domain_name != "" ? "${var.enable_https ? "https" : "http"}://${var.domain_name}" : null
}

output "hostinger_cname_instructions" {
  description = "CNAME record to add in Hostinger DNS Zone Editor to point your subdomain to the ALB"
  value = var.domain_name != "" ? {
    record_type = "CNAME"
    host_name   = var.domain_name
    points_to   = aws_lb.main.dns_name
    ttl         = 300
  } : null
}

output "acm_dns_validation_records" {
  description = "ACM DNS validation CNAME record(s) to add in Hostinger to validate your HTTPS certificate"
  value = length(aws_acm_certificate.main) > 0 ? [
    for dvo in aws_acm_certificate.main[0].domain_validation_options : {
      domain_name  = dvo.domain_name
      record_name  = dvo.resource_record_name
      record_type  = dvo.resource_record_type
      record_value = dvo.resource_record_value
    }
  ] : []
}

output "ecr_backend_repository_url" {
  description = "Amazon ECR repository URL for the Medusa backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_storefront_repository_url" {
  description = "Amazon ECR repository URL for the Next.js storefront image"
  value       = aws_ecr_repository.storefront.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS Fargate cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_backend_service_name" {
  description = "Name of the Medusa backend ECS service"
  value       = aws_ecs_service.backend.name
}

output "ecs_storefront_service_name" {
  description = "Name of the Next.js storefront ECS service"
  value       = aws_ecs_service.storefront.name
}

output "rds_endpoint" {
  description = "Private endpoint of the Amazon RDS PostgreSQL instance"
  value       = aws_db_instance.postgres.endpoint
}

output "redis_endpoint" {
  description = "Private endpoint of the Amazon ElastiCache Redis cluster"
  value       = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

output "secrets_manager_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret storing application runtime credentials"
  value       = aws_secretsmanager_secret.app.arn
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC authentication (save as AWS_ROLE_ARN in GitHub Actions)"
  value       = aws_iam_role.github_actions.arn
}
