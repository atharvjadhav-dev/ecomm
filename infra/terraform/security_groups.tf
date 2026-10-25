# ------------------------------------------------------------------------------
# 1. Application Load Balancer Security Group (Public HTTP/HTTPS)
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow public HTTP and HTTPS traffic to the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic to VPC targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

# ------------------------------------------------------------------------------
# 2. Storefront ECS Task Security Group (Private Subnet, Port 8000 from ALB only)
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_storefront" {
  name        = "${local.name_prefix}-ecs-storefront-sg"
  description = "Allow port 8000 from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP 8000 from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound traffic (NAT, ECR, Backend Service Connect)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-storefront-sg"
  }
}

# ------------------------------------------------------------------------------
# 3. Backend ECS Task Security Group (Private Subnet, Port 9000 from ALB & Storefront)
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_backend" {
  name        = "${local.name_prefix}-ecs-backend-sg"
  description = "Allow port 9000 from ALB and Storefront ECS task"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP 9000 from ALB and Storefront"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id, aws_security_group.ecs_storefront.id]
  }

  egress {
    description = "Allow outbound traffic (RDS, Redis, NAT, ECR)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-backend-sg"
  }
}

# ------------------------------------------------------------------------------
# 4. RDS PostgreSQL Security Group (Private Subnet, Port 5432 from Backend ECS only)
# ------------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow PostgreSQL 5432 from Backend ECS task only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Medusa backend ECS task"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

# ------------------------------------------------------------------------------
# 5. ElastiCache Redis Security Group (Private Subnet, Port 6379 from Backend ECS only)
# ------------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Allow Redis 6379 from Medusa backend ECS task only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from Medusa backend ECS task"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  tags = {
    Name = "${local.name_prefix}-redis-sg"
  }
}
