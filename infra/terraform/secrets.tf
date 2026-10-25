resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "random_password" "cookie_secret" {
  length  = 48
  special = false
}

resource "random_password" "admin_password" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.name_prefix}/app-secrets"
  description             = "Runtime secrets for Medusa backend and Next.js storefront ECS tasks"
  recovery_window_in_days = 0

  tags = {
    Name = "${local.name_prefix}-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    POSTGRES_PASSWORD                  = random_password.db_password.result
    DATABASE_URL                       = "postgres://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${var.db_name}"
    JWT_SECRET                         = random_password.jwt_secret.result
    COOKIE_SECRET                      = random_password.cookie_secret.result
    STOREFRONT_PUBLISHABLE_KEY         = var.storefront_publishable_key
    NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY = var.storefront_publishable_key
    ADMIN_EMAIL                        = var.admin_email
    ADMIN_PASSWORD                     = random_password.admin_password.result
  })
}
