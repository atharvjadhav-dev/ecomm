# ------------------------------------------------------------------------------
# 1. ACM Certificate (DNS Validation for Hostinger)
# ------------------------------------------------------------------------------
resource "aws_acm_certificate" "main" {
  count             = var.existing_acm_certificate_arn == "" && var.domain_name != "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-acm-cert"
  }
}

locals {
  certificate_arn = var.existing_acm_certificate_arn != "" ? var.existing_acm_certificate_arn : (
    length(aws_acm_certificate.main) > 0 ? aws_acm_certificate.main[0].arn : ""
  )
}

# ------------------------------------------------------------------------------
# 2. Application Load Balancer
# ------------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# ------------------------------------------------------------------------------
# 3. Target Groups (Backend :9000 and Storefront :8000)
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "backend" {
  name        = "${local.name_prefix}-be-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 4
  }

  tags = {
    Name = "${local.name_prefix}-backend-tg"
  }
}

resource "aws_lb_target_group" "storefront" {
  name        = "${local.name_prefix}-sf-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 4
  }

  tags = {
    Name = "${local.name_prefix}-storefront-tg"
  }
}

# ------------------------------------------------------------------------------
# 4. HTTP (Port 80) Listener
#    - When enable_https = false: serves Storefront & Backend path rules over HTTP
#    - When enable_https = true: redirects HTTP -> HTTPS (443)
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.enable_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.enable_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.storefront.arn
    }
  }
}

resource "aws_lb_listener_rule" "http_backend_paths" {
  count        = var.enable_https ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = [
        "/store/*",
        "/admin/*",
        "/auth/*",
        "/health"
      ]
    }
  }
}

resource "aws_lb_listener_rule" "http_backend_admin_ui" {
  count        = var.enable_https ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = [
        "/app",
        "/app/*"
      ]
    }
  }
}

# ------------------------------------------------------------------------------
# 5. HTTPS (Port 443) Listener (Active when enable_https = true after ACM DNS validation)
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.storefront.arn
  }
}

resource "aws_lb_listener_rule" "https_backend_paths" {
  count        = var.enable_https ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = [
        "/store/*",
        "/admin/*",
        "/auth/*",
        "/health"
      ]
    }
  }
}

resource "aws_lb_listener_rule" "https_backend_admin_ui" {
  count        = var.enable_https ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = [
        "/app",
        "/app/*"
      ]
    }
  }
}
