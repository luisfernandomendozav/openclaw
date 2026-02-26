# HANA CloudFormation Infrastructure

This directory contains AWS CloudFormation templates for deploying the HANA application infrastructure.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Infrastructure                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Internet → WAF → ALB (public subnets)                      │
│                    │                                         │
│         ┌─────────┼─────────┐                               │
│    hana-api   hana-ws   hana-workers                        │
│    (Fargate)  (Fargate)  (Fargate)                          │
│         │        │         │                                 │
│         └────────┼─────────┘                                │
│                  │ (private subnets)                        │
│    ┌─────────────┼─────────────┐                           │
│  RDS PostgreSQL  ElastiCache   SQS FIFO                    │
│  (Multi-AZ)      Redis         (agent-runs)                │
│         │                                                   │
│      S3 Buckets (media, exports, artifacts)                │
│                                                              │
│  Observability: CloudWatch, X-Ray, SNS                     │
└─────────────────────────────────────────────────────────────┘
```

## Stack Components

| Stack             | File                 | Description                                               |
| ----------------- | -------------------- | --------------------------------------------------------- |
| **network**       | `network.yaml`       | VPC, subnets, NAT gateway, security groups, VPC endpoints |
| **storage**       | `storage.yaml`       | ECR repository, S3 buckets (media, exports, artifacts)    |
| **secrets**       | `secrets.yaml`       | Secrets Manager for API keys, DB credentials, JWT         |
| **messaging**     | `messaging.yaml`     | SQS FIFO queues for agent runs, notifications             |
| **database**      | `database.yaml`      | RDS PostgreSQL, ElastiCache Redis                         |
| **iam**           | `iam.yaml`           | IAM roles for ECS, Lambda, API Gateway                    |
| **compute**       | `compute.yaml`       | ECS cluster, ALB, Fargate services, auto-scaling          |
| **waf**           | `waf.yaml`           | WAF WebACL with rate limiting, managed rules              |
| **observability** | `observability.yaml` | CloudWatch dashboard, alarms, SNS topics                  |
| **main**          | `main.yaml`          | Master stack for nested deployment                        |

## Quick Start

### Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Sufficient IAM permissions to create all resources

### AWS SSO Login

The scripts use AWS SSO with the `my-dev-profile` profile by default:

```bash
# Login to AWS SSO
./deploy.sh --login

# Or login separately
aws sso login --profile my-dev-profile

# Use a different profile
./deploy.sh --profile other-profile --environment dev
```

### Deploy All Stacks

```bash
# Deploy to dev environment
./deploy.sh --environment dev --alarm-email your@email.com

# Deploy to production
./deploy.sh --environment prod --alarm-email ops@example.com
```

### Deploy Individual Stack

```bash
# Deploy only the network stack
./deploy.sh --stack network --environment dev

# Deploy only compute (after dependencies are deployed)
./deploy.sh --stack compute --environment dev
```

### Check Status

```bash
./deploy.sh --status --environment dev
```

### Delete Infrastructure

```bash
# Delete all stacks (prompts for confirmation)
./deploy.sh --delete --environment dev

# Delete specific stack
./deploy.sh --delete --stack compute --environment dev
```

## Configuration

### Environment Variables

Set these before running the deploy script:

```bash
export AWS_REGION=us-east-1
export ENVIRONMENT=dev
export PROJECT_NAME=hana
```

### Stack Parameters

Key parameters that can be customized:

| Parameter         | Default          | Description                 |
| ----------------- | ---------------- | --------------------------- |
| `DBInstanceClass` | db.t4g.medium    | RDS instance size           |
| `RedisNodeType`   | cache.t4g.medium | ElastiCache node size       |
| `ApiCpu`          | 512              | CPU units for API tasks     |
| `ApiMemory`       | 1024             | Memory (MB) for API tasks   |
| `ApiDesiredCount` | 1                | Number of API task replicas |
| `RateLimitPerIP`  | 2000             | WAF rate limit (per 5 min)  |

### Environment-Specific Behavior

| Feature             | Dev       | Staging   | Prod       |
| ------------------- | --------- | --------- | ---------- |
| NAT Gateways        | 1         | 1         | 2 (HA)     |
| RDS Multi-AZ        | No        | No        | Yes        |
| Redis Replicas      | 0         | 0         | 1          |
| Auto-scaling        | 1-4 tasks | 1-4 tasks | 2-20 tasks |
| Log Retention       | 7 days    | 14 days   | 30 days    |
| Deletion Protection | No        | No        | Yes        |

## Post-Deployment Setup

### 1. Update API Keys

After deployment, update the placeholder secrets:

```bash
# Anthropic API Key
aws secretsmanager put-secret-value \
  --secret-id hana/dev/anthropic-api-key \
  --secret-string '{"api_key": "sk-ant-YOUR-KEY-HERE"}'

# OpenAI API Key (optional)
aws secretsmanager put-secret-value \
  --secret-id hana/dev/openai-api-key \
  --secret-string '{"api_key": "sk-YOUR-KEY-HERE"}'

# ElevenLabs API Key (optional)
aws secretsmanager put-secret-value \
  --secret-id hana/dev/elevenlabs-api-key \
  --secret-string '{"api_key": "YOUR-KEY-HERE"}'
```

### 2. Build and Push Docker Image

```bash
cd /path/to/openclaw

# Build the image
./scripts/deploy-aws.sh --environment dev
```

### 3. Verify Deployment

```bash
# Get ALB DNS
ALB_DNS=$(aws cloudformation describe-stacks \
  --stack-name hana-dev-compute \
  --query 'Stacks[0].Outputs[?OutputKey==`ALBDNSName`].OutputValue' \
  --output text)

# Check health
curl "http://${ALB_DNS}/health"
```

## Cost Estimation

### Development (~$260/month)

- RDS db.t4g.medium: ~$50
- ElastiCache cache.t4g.medium: ~$30
- NAT Gateway: ~$35
- ECS Fargate (3 tasks): ~$100
- ALB: ~$25
- Other (S3, CloudWatch, etc.): ~$20

### Production (~$1,200/month)

- RDS db.r6g.large Multi-AZ: ~$300
- ElastiCache cache.r6g.large with replica: ~$200
- 2x NAT Gateways: ~$70
- ECS Fargate (scaling 2-20 tasks): ~$400+
- ALB: ~$25
- WAF: ~$50
- Other: ~$100+

## Troubleshooting

### Stack Creation Failed

1. Check CloudFormation events in AWS Console
2. Look for specific error messages
3. Common issues:
   - Insufficient IAM permissions
   - Resource limits exceeded
   - Dependency not ready

### Services Not Starting

1. Check ECS service events: `aws ecs describe-services --cluster hana-dev --services hana-dev-api`
2. Check container logs: `aws logs tail /ecs/hana-dev/api --follow`
3. Verify secrets are populated
4. Check security group rules

### Database Connection Issues

1. Verify RDS is in "available" state
2. Check security groups allow traffic from ECS
3. Confirm secrets have correct credentials

## Security Features

- **Network Isolation**: RDS and Redis in private subnets with no internet access
- **Encryption**: All data encrypted at rest (RDS, Redis, S3, SQS)
- **WAF Protection**: AWS managed rules for OWASP Top 10, rate limiting
- **Secrets Management**: All sensitive data in AWS Secrets Manager
- **IAM Least Privilege**: Minimal permissions for each service role
- **VPC Endpoints**: Reduced exposure through private AWS service access

## Files

```
cloudformation/
├── README.md           # This file
├── deploy.sh           # Deployment script
├── main.yaml           # Master stack (for nested deployment)
├── network.yaml        # VPC, subnets, security groups
├── storage.yaml        # ECR, S3 buckets
├── secrets.yaml        # Secrets Manager
├── messaging.yaml      # SQS queues
├── database.yaml       # RDS PostgreSQL, ElastiCache Redis
├── iam.yaml            # IAM roles and policies
├── compute.yaml        # ECS cluster, ALB, Fargate services
├── waf.yaml            # WAF WebACL
└── observability.yaml  # CloudWatch, alarms, dashboard
```
