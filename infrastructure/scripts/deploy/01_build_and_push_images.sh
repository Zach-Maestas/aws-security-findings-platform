#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 01_build_and_push_images.sh
# Purpose: Build and push Docker images to ECR for API and DB Init containers
# Usage: ./01_build_and_push_images.sh
# ==============================================================================

echo "==> Step 1: Building and pushing Docker images to ECR"

# Set project name
PROJECT_NAME="secops-pipeline"

# Navigate to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Define context paths
API_CTX="${REPO_ROOT}/application/backend"
DB_INIT_CTX="${REPO_ROOT}/infrastructure/scripts/db-init"

# Get AWS account and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-$(aws configure get region)}

# ECR repository URIs
API_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-api-repo"
DB_INIT_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-db-init-repo"

echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "AWS Region: ${AWS_REGION}"
echo ""
echo "API Repository: ${API_REPO_URI}"
echo "DB Init Repository: ${DB_INIT_REPO_URI}"
echo ""

# Login to ECR
echo "==> Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Build and push API image
echo ""
echo "==> Building and pushing API image..."
docker buildx build \
  --platform linux/amd64 \
  -t "${API_REPO_URI}:latest" \
  --push \
  "${API_CTX}"

# Build and push DB Init image
echo ""
echo "==> Building and pushing DB Init image..."
docker buildx build \
  --platform linux/amd64 \
  -t "${DB_INIT_REPO_URI}:latest" \
  --push \
  "${DB_INIT_CTX}"

echo ""
echo "✅ Images built and pushed successfully!"
echo ""
echo "Next step: Run ./02_run_db_init.sh to initialize the database"
