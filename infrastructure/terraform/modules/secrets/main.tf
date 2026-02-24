/*
==============================================================================
Secrets Module: Application Database Credentials
==============================================================================
Generates and stores application-level database credentials in Secrets Manager.
The application uses a least-privilege database role (not the master user).
==============================================================================
*/

# Generate random password for application database user
# Excludes problematic characters for PostgreSQL password handling
resource "random_password" "db_app_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secrets Manager secret for application database credentials
resource "aws_secretsmanager_secret" "db_app_credentials" {
  name                    = "${var.project}/db-app"
  recovery_window_in_days = 0 # force immediate deletion for teardown/rebuild cycles

  tags = {
    Name = "${var.project}-db-app-credentials"
  }
}

# Store application database username and password in Secrets Manager
resource "aws_secretsmanager_secret_version" "db_app_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_app_credentials.id
  secret_string = jsonencode({
    username = var.db_app_username
    password = random_password.db_app_password.result
  })
}