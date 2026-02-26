#!/usr/bin/env bash
set -euo pipefail

# HANA AWS Deployment Script
#
# Builds Docker image, pushes to ECR, and deploys to ECS.
# Integrates with CloudFormation stack outputs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-hana}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
AWS_PROFILE="${AWS_PROFILE:-my-dev-profile}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}ℹ️  $1${NC}"
}

log_warn() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploy HANA to AWS ECS.

OPTIONS:
  -e, --environment ENV    Environment (dev, staging, prod) [default: dev]
  -r, --region REGION      AWS region [default: us-east-1]
  -p, --profile PROFILE    AWS CLI profile (SSO supported) [default: my-dev-profile]
  -t, --tag TAG           Docker image tag [default: latest]
  -s, --service SERVICE   Deploy specific service (api, ws, workers, all) [default: all]
  --skip-build            Skip Docker build step
  --skip-push             Skip ECR push step
  --login                 Run AWS SSO login before deployment
  -h, --help              Show this help message

EXAMPLES:
  # Login to AWS SSO first
  $0 --login

  # Deploy to dev environment
  $0 --environment dev

  # Deploy to production with custom tag
  $0 --environment prod --tag v1.0.0

  # Deploy only the API service
  $0 --service api

  # Skip build and just deploy
  $0 --skip-build --skip-push
EOF
  exit 1
}

# Parse arguments
SKIP_BUILD=false
SKIP_PUSH=false
SERVICE="all"
DO_LOGIN=false

while [[ $# -gt 0 ]]; do
  case $1 in
  -e | --environment)
    ENVIRONMENT="$2"
    shift 2
    ;;
  -r | --region)
    AWS_REGION="$2"
    shift 2
    ;;
  -p | --profile)
    AWS_PROFILE="$2"
    shift 2
    ;;
  -t | --tag)
    IMAGE_TAG="$2"
    shift 2
    ;;
  -s | --service)
    SERVICE="$2"
    shift 2
    ;;
  --skip-build)
    SKIP_BUILD=true
    shift
    ;;
  --skip-push)
    SKIP_PUSH=true
    shift
    ;;
  --login)
    DO_LOGIN=true
    shift
    ;;
  -h | --help)
    usage
    ;;
  *)
    log_error "Unknown option: $1"
    usage
    ;;
  esac
done

# Export AWS_PROFILE for all AWS CLI commands
export AWS_PROFILE

# SSO Login if requested
if [ "$DO_LOGIN" = true ]; then
  log_info "Logging in to AWS SSO..."
  aws sso login --profile "$AWS_PROFILE"
  log_info "SSO login successful"
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  log_error "Invalid environment: $ENVIRONMENT (must be dev, staging, or prod)"
  exit 1
fi

# Verify AWS credentials
log_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
  log_error "AWS credentials not valid. Run with --login to authenticate via SSO."
  log_info "Example: $0 --login --environment $ENVIRONMENT"
  exit 1
fi

# Get AWS account ID
log_info "Getting AWS account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

log_info "Configuration:"
echo "  Environment: $ENVIRONMENT"
echo "  AWS Region: $AWS_REGION"
echo "  AWS Profile: $AWS_PROFILE"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo "  Image Tag: $IMAGE_TAG"
echo "  Service: $SERVICE"
echo ""

# Build Docker image
if [ "$SKIP_BUILD" = false ]; then
  log_info "Building Docker image..."
  cd "$PROJECT_ROOT"
  docker build -t "$PROJECT_NAME:$IMAGE_TAG" .
  log_info "✅ Docker image built successfully"
else
  log_warn "Skipping Docker build"
fi

# Push to ECR
if [ "$SKIP_PUSH" = false ]; then
  log_info "Logging in to ECR..."
  aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" |
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

  # Get ECR repository URIs from CloudFormation stack outputs
  STACK_NAME="$PROJECT_NAME-$ENVIRONMENT"

  log_info "Getting ECR repository URIs from CloudFormation stack..."
  API_ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiECRUri'].OutputValue" \
    --output text \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" 2>/dev/null || echo "")

  if [ -z "$API_ECR_URI" ]; then
    log_warn "CloudFormation stack not found. Using default ECR repository names..."
    API_ECR_URI="$ECR_REGISTRY/$PROJECT_NAME-$ENVIRONMENT/api"
  fi

  # For hybrid deployment, use the same image for all services
  log_info "Tagging and pushing image to ECR..."
  docker tag "$PROJECT_NAME:$IMAGE_TAG" "$API_ECR_URI:$IMAGE_TAG"
  docker push "$API_ECR_URI:$IMAGE_TAG"

  log_info "✅ Image pushed to ECR: $API_ECR_URI:$IMAGE_TAG"
else
  log_warn "Skipping ECR push"
fi

# Deploy to ECS
log_info "Deploying to ECS..."
CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT"

# Function to update ECS service
update_service() {
  local service_name=$1
  log_info "Updating ECS service: $service_name..."

  aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$service_name" \
    --force-new-deployment \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --output json >/dev/null

  log_info "Service $service_name updated"
}

# Deploy services
case "$SERVICE" in
api)
  update_service "$PROJECT_NAME-$ENVIRONMENT-api"
  ;;
ws)
  update_service "$PROJECT_NAME-$ENVIRONMENT-ws"
  ;;
workers)
  update_service "$PROJECT_NAME-$ENVIRONMENT-workers"
  ;;
all)
  update_service "$PROJECT_NAME-$ENVIRONMENT-api"
  update_service "$PROJECT_NAME-$ENVIRONMENT-ws"
  update_service "$PROJECT_NAME-$ENVIRONMENT-workers"
  ;;
*)
  log_error "Invalid service: $SERVICE (must be api, ws, workers, or all)"
  exit 1
  ;;
esac

log_info "🎉 Deployment completed successfully!"
log_info ""
log_info "Next steps:"
log_info "  1. Monitor deployment: aws ecs describe-services --cluster $CLUSTER_NAME --services $PROJECT_NAME-$ENVIRONMENT-api --region $AWS_REGION"
log_info "  2. View logs: aws logs tail /ecs/$PROJECT_NAME-$ENVIRONMENT/api --follow --region $AWS_REGION"
log_info "  3. Check health: curl https://\$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==\"RestApiUrl\"].OutputValue' --output text)/health"
