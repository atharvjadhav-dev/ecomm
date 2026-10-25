# ------------------------------------------------------------------------------
# 1. CloudWatch Log Groups
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}/backend"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-backend-logs"
  }
}

resource "aws_cloudwatch_log_group" "storefront" {
  name              = "/ecs/${local.name_prefix}/storefront"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-storefront-logs"
  }
}

# ------------------------------------------------------------------------------
# 2. ECS Cluster & Service Connect Namespace
# ------------------------------------------------------------------------------
resource "aws_service_discovery_http_namespace" "main" {
  name        = "${local.name_prefix}.internal"
  description = "ECS Service Connect namespace for internal storefront-to-backend communication"
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.main.arn
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# ------------------------------------------------------------------------------
# 3. IAM Roles (Least-Privilege Task Execution Role & Task Role)
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_secrets_access" {
  statement {
    sid       = "ReadAppSecretsFromSecretsManager"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app.arn]
  }
}

resource "aws_iam_role_policy" "ecs_secrets_access" {
  name   = "${local.name_prefix}-ecs-secrets-policy"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_secrets_access.json
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# ------------------------------------------------------------------------------
# 4. Computed Origins & CORS
# ------------------------------------------------------------------------------
locals {
  alb_http_origin     = "http://${aws_lb.main.dns_name}"
  domain_http_origin  = var.domain_name != "" ? "http://${var.domain_name}" : ""
  domain_https_origin = var.domain_name != "" ? "https://${var.domain_name}" : ""

  public_base_url = var.enable_https && var.domain_name != "" ? local.domain_https_origin : local.alb_http_origin

  allowed_cors_origins = join(",", compact([
    local.alb_http_origin,
    local.domain_http_origin,
    local.domain_https_origin,
    "http://backend:9000",
    "http://storefront:8000"
  ]))
}

# ------------------------------------------------------------------------------
# 5. Medusa Backend Task Definition & Service (Desired Count = 1)
# ------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.backend_cpu)
  memory                   = tostring(var.backend_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:${var.backend_image_tag}"
      essential = true

      portMappings = [
        {
          name          = "http"
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = "9000" },
        { name = "DATABASE_SSL", value = "true" },
        { name = "DATABASE_SSL_REJECT_UNAUTHORIZED", value = "false" },
        { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}" },
        { name = "COOKIE_SECURE", value = tostring(var.enable_https) },
        { name = "STORE_CORS", value = local.allowed_cors_origins },
        { name = "ADMIN_CORS", value = local.allowed_cors_origins },
        { name = "AUTH_CORS", value = local.allowed_cors_origins }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:DATABASE_URL::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:JWT_SECRET::"
        },
        {
          name      = "COOKIE_SECRET"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:COOKIE_SECRET::"
        },
        {
          name      = "STOREFRONT_PUBLISHABLE_KEY"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:STOREFRONT_PUBLISHABLE_KEY::"
        },
        {
          name      = "ADMIN_EMAIL"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:ADMIN_EMAIL::"
        },
        {
          name      = "ADMIN_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:ADMIN_PASSWORD::"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9000/health || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 5
        startPeriod = 120
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-backend-td"
  }
}

resource "aws_ecs_service" "backend" {
  name                              = "${local.name_prefix}-backend"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.backend.arn
  desired_count                     = var.backend_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 180

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_backend.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 9000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "http"
      discovery_name = "backend"

      client_alias {
        port     = 9000
        dns_name = "backend"
      }
    }
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener_rule.http_backend_paths,
    aws_lb_listener_rule.http_backend_admin_ui,
    aws_lb_listener_rule.https_backend_paths,
    aws_lb_listener_rule.https_backend_admin_ui,
    aws_db_instance.postgres,
    aws_elasticache_cluster.redis,
    aws_secretsmanager_secret_version.app
  ]

  tags = {
    Name = "${local.name_prefix}-backend-svc"
  }
}

# ------------------------------------------------------------------------------
# 6. Next.js Storefront Task Definition & Service (Desired Count = 1)
# ------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "storefront" {
  family                   = "${local.name_prefix}-storefront"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.storefront_cpu)
  memory                   = tostring(var.storefront_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "storefront"
      image     = "${aws_ecr_repository.storefront.repository_url}:${var.storefront_image_tag}"
      essential = true

      portMappings = [
        {
          name          = "http"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = "8000" },
        { name = "MEDUSA_BACKEND_URL", value = "http://backend:9000" },
        { name = "NEXT_PUBLIC_MEDUSA_BACKEND_URL", value = local.public_base_url },
        { name = "NEXT_PUBLIC_BASE_URL", value = local.public_base_url },
        { name = "NEXT_PUBLIC_DEFAULT_REGION", value = var.default_region_code },
        { name = "COOKIE_SECURE", value = tostring(var.enable_https) }
      ]

      secrets = [
        {
          name      = "NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY"
          valueFrom = "${aws_secretsmanager_secret.app.arn}:NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY::"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000 || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 45
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.storefront.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-storefront-td"
  }
}

resource "aws_ecs_service" "storefront" {
  name                              = "${local.name_prefix}-storefront"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.storefront.arn
  desired_count                     = var.storefront_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_storefront.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.storefront.arn
    container_name   = "storefront"
    container_port   = 8000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn
  }

  depends_on = [
    aws_lb_listener.http,
    aws_ecs_service.backend
  ]

  tags = {
    Name = "${local.name_prefix}-storefront-svc"
  }
}
