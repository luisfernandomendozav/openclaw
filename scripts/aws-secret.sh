#!/usr/bin/env bash
# AWS Secrets Manager helper script
# Usage: ./scripts/aws-secret.sh <action> <secret-name> [value]

set -e

PROFILE="${AWS_PROFILE:-my-dev-profile}"
PREFIX="hana/dev"

action="${1:-help}"
secret_name="${2:-}"
secret_value="${3:-}"

case "$action" in
  set)
    if [ -z "$secret_name" ] || [ -z "$secret_value" ]; then
      echo "Usage: $0 set <secret-name> <api-key>"
      echo "Example: $0 set anthropic sk-ant-api03-xxxxx"
      exit 1
    fi

    case "$secret_name" in
      anthropic)
        aws secretsmanager put-secret-value \
          --secret-id "$PREFIX/anthropic-api-key" \
          --secret-string "{\"api_key\": \"$secret_value\"}" \
          --profile "$PROFILE"
        echo "✅ Anthropic API key updated"
        ;;
      openai)
        aws secretsmanager put-secret-value \
          --secret-id "$PREFIX/openai-api-key" \
          --secret-string "{\"api_key\": \"$secret_value\"}" \
          --profile "$PROFILE"
        echo "✅ OpenAI API key updated"
        ;;
      elevenlabs)
        aws secretsmanager put-secret-value \
          --secret-id "$PREFIX/elevenlabs-api-key" \
          --secret-string "{\"api_key\": \"$secret_value\"}" \
          --profile "$PROFILE"
        echo "✅ ElevenLabs API key updated"
        ;;
      *)
        echo "Unknown secret: $secret_name"
        echo "Available: anthropic, openai, elevenlabs"
        exit 1
        ;;
    esac
    ;;

  get)
    if [ -z "$secret_name" ]; then
      echo "Usage: $0 get <secret-name>"
      exit 1
    fi

    case "$secret_name" in
      anthropic) secret_id="$PREFIX/anthropic-api-key" ;;
      openai) secret_id="$PREFIX/openai-api-key" ;;
      elevenlabs) secret_id="$PREFIX/elevenlabs-api-key" ;;
      rds) secret_id="$PREFIX/rds-master" ;;
      redis) secret_id="$PREFIX/redis-auth" ;;
      jwt) secret_id="$PREFIX/jwt-secret" ;;
      gateway) secret_id="$PREFIX/gateway-token" ;;
      *) secret_id="$PREFIX/$secret_name" ;;
    esac

    aws secretsmanager get-secret-value \
      --secret-id "$secret_id" \
      --profile "$PROFILE" \
      --query 'SecretString' --output text
    ;;

  list)
    aws secretsmanager list-secrets \
      --profile "$PROFILE" \
      --query 'SecretList[?contains(Name, `hana/dev`)].Name' \
      --output table
    ;;

  help|*)
    cat <<EOF
AWS Secrets Manager Helper

Usage: $0 <action> [args]

Actions:
  set <name> <key>   Set an API key
  get <name>         Get a secret value
  list               List all HANA secrets

Examples:
  $0 set anthropic sk-ant-api03-xxxxx
  $0 set openai sk-xxxxx
  $0 set elevenlabs xxxxx
  $0 get anthropic
  $0 get rds
  $0 list

After updating secrets, restart services:
  pnpm aws:restart:api
EOF
    ;;
esac
