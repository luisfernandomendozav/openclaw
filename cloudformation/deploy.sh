#!/usr/bin/env bash
set -euo pipefail

# HANA CloudFormation Deployment Script
#
# Deploys all CloudFormation stacks in the correct order.
# Can deploy individual stacks or the entire infrastructure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-hana}"
AWS_PROFILE="${AWS_PROFILE:-my-dev-profile}"
ALARM_EMAIL=""
ACTION="deploy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
  echo -e "${BLUE}[STEP]${NC} $1"
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploy HANA CloudFormation infrastructure to AWS.

OPTIONS:
  -e, --environment ENV    Environment (dev, staging, prod) [default: dev]
  -r, --region REGION      AWS region [default: us-east-1]
  -p, --profile PROFILE    AWS CLI profile (SSO supported) [default: my-dev-profile]
  -a, --alarm-email EMAIL  Email for CloudWatch alarms (optional)
  --stack STACK            Deploy specific stack only (network, storage, secrets, etc.)
  --delete                 Delete the stack instead of deploying
  --status                 Show stack status
  --login                  Run AWS SSO login before deployment
  -h, --help               Show this help message

EXAMPLES:
  # Login to AWS SSO first
  $0 --login

  # Deploy all stacks to dev environment
  $0 --environment dev --alarm-email alerts@example.com

  # Deploy only the network stack
  $0 --stack network --environment dev

  # Deploy to production
  $0 --environment prod --alarm-email ops@example.com

  # Check stack status
  $0 --status --environment dev

  # Delete all stacks
  $0 --delete --environment dev
EOF
  exit 1
}

# Parse arguments
SPECIFIC_STACK=""
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
  -a | --alarm-email)
    ALARM_EMAIL="$2"
    shift 2
    ;;
  --stack)
    SPECIFIC_STACK="$2"
    shift 2
    ;;
  --delete)
    ACTION="delete"
    shift
    ;;
  --status)
    ACTION="status"
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

# Stack names in deployment order
STACKS=(
  "network"
  "storage"
  "secrets"
  "messaging"
  "database"
  "iam"
  "compute"
  "waf"
  "observability"
)

get_stack_name() {
  local stack=$1
  echo "${PROJECT_NAME}-${ENVIRONMENT}-${stack}"
}

get_template_path() {
  local stack=$1
  echo "${SCRIPT_DIR}/${stack}.yaml"
}

# Check if a stack exists
stack_exists() {
  local stack_name=$1
  aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "DOES_NOT_EXIST"
}

# Wait for stack operation to complete
wait_for_stack() {
  local stack_name=$1
  local operation=$2 # create, update, delete

  log_info "Waiting for stack $stack_name to complete $operation..."

  case $operation in
  create)
    aws cloudformation wait stack-create-complete \
      --stack-name "$stack_name" \
      --region "$AWS_REGION"
    ;;
  update)
    aws cloudformation wait stack-update-complete \
      --stack-name "$stack_name" \
      --region "$AWS_REGION"
    ;;
  delete)
    aws cloudformation wait stack-delete-complete \
      --stack-name "$stack_name" \
      --region "$AWS_REGION"
    ;;
  esac
}

# Build parameters for a stack
build_parameters() {
  local stack=$1
  local params="ProjectName=${PROJECT_NAME} Environment=${ENVIRONMENT}"

  case $stack in
  observability)
    if [ -n "$ALARM_EMAIL" ]; then
      params="$params AlarmEmail=${ALARM_EMAIL}"
    fi
    ;;
  esac

  echo "$params"
}

# Deploy a single stack
deploy_stack() {
  local stack=$1
  local stack_name
  local template_path
  local status

  stack_name=$(get_stack_name "$stack")
  template_path=$(get_template_path "$stack")

  if [ ! -f "$template_path" ]; then
    log_error "Template not found: $template_path"
    return 1
  fi

  log_step "Deploying stack: $stack_name"

  status=$(stack_exists "$stack_name")

  local params
  params=$(build_parameters "$stack")

  # Convert params to CloudFormation format
  local cf_params=""
  for param in $params; do
    key=$(echo "$param" | cut -d= -f1)
    value=$(echo "$param" | cut -d= -f2)
    cf_params="$cf_params ParameterKey=$key,ParameterValue=$value"
  done

  if [ "$status" = "DOES_NOT_EXIST" ]; then
    log_info "Creating new stack: $stack_name"
    aws cloudformation create-stack \
      --stack-name "$stack_name" \
      --template-body "file://${template_path}" \
      --parameters $cf_params \
      --capabilities CAPABILITY_NAMED_IAM \
      --region "$AWS_REGION" \
      --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value="$PROJECT_NAME"

    wait_for_stack "$stack_name" "create"
  else
    log_info "Updating existing stack: $stack_name"
    if aws cloudformation update-stack \
      --stack-name "$stack_name" \
      --template-body "file://${template_path}" \
      --parameters $cf_params \
      --capabilities CAPABILITY_NAMED_IAM \
      --region "$AWS_REGION" 2>&1 | grep -q "No updates are to be performed"; then
      log_info "No updates needed for $stack_name"
    else
      wait_for_stack "$stack_name" "update"
    fi
  fi

  log_info "Stack $stack_name deployed successfully"
}

# Delete a single stack
delete_stack() {
  local stack=$1
  local stack_name
  local status

  stack_name=$(get_stack_name "$stack")
  status=$(stack_exists "$stack_name")

  if [ "$status" = "DOES_NOT_EXIST" ]; then
    log_warn "Stack $stack_name does not exist, skipping"
    return 0
  fi

  log_step "Deleting stack: $stack_name"

  aws cloudformation delete-stack \
    --stack-name "$stack_name" \
    --region "$AWS_REGION"

  wait_for_stack "$stack_name" "delete"

  log_info "Stack $stack_name deleted successfully"
}

# Show stack status
show_status() {
  local stack=$1
  local stack_name
  local status

  stack_name=$(get_stack_name "$stack")
  status=$(stack_exists "$stack_name")

  printf "%-30s %s\n" "$stack_name" "$status"
}

# Main execution
main() {
  log_info "HANA CloudFormation Deployment"
  echo "  Environment: $ENVIRONMENT"
  echo "  AWS Region: $AWS_REGION"
  echo "  AWS Profile: $AWS_PROFILE"
  echo "  Action: $ACTION"
  echo ""

  # Verify AWS credentials
  if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
    log_error "AWS credentials not valid. Run with --login to authenticate via SSO."
    log_info "Example: $0 --login --environment $ENVIRONMENT"
    exit 1
  fi

  case $ACTION in
  deploy)
    if [ -n "$SPECIFIC_STACK" ]; then
      deploy_stack "$SPECIFIC_STACK"
    else
      log_info "Deploying all stacks in order..."
      for stack in "${STACKS[@]}"; do
        deploy_stack "$stack"
      done
      log_info "All stacks deployed successfully!"

      # Print outputs
      echo ""
      log_info "Stack Outputs:"
      echo "  ALB DNS: $(aws cloudformation describe-stacks --stack-name "$(get_stack_name compute)" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`ALBDNSName`].OutputValue' --output text 2>/dev/null || echo 'N/A')"
      echo "  ECR URI: $(aws cloudformation describe-stacks --stack-name "$(get_stack_name storage)" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`ApiRepositoryUri`].OutputValue' --output text 2>/dev/null || echo 'N/A')"
    fi
    ;;
  delete)
    if [ -n "$SPECIFIC_STACK" ]; then
      delete_stack "$SPECIFIC_STACK"
    else
      log_warn "Deleting all stacks in reverse order..."
      read -p "Are you sure you want to delete all stacks? (yes/no): " confirm
      if [ "$confirm" != "yes" ]; then
        log_info "Aborted"
        exit 0
      fi

      # Delete in reverse order
      for ((i = ${#STACKS[@]} - 1; i >= 0; i--)); do
        delete_stack "${STACKS[$i]}"
      done
      log_info "All stacks deleted successfully!"
    fi
    ;;
  status)
    log_info "Stack Status:"
    echo ""
    printf "%-30s %s\n" "STACK NAME" "STATUS"
    printf "%-30s %s\n" "----------" "------"
    if [ -n "$SPECIFIC_STACK" ]; then
      show_status "$SPECIFIC_STACK"
    else
      for stack in "${STACKS[@]}"; do
        show_status "$stack"
      done
    fi
    ;;
  esac
}

main
