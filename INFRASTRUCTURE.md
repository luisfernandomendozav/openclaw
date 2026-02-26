# HANA AWS Infrastructure

Complete AWS infrastructure for HANA deployed via CloudFormation.

## Infrastructure Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WAF (Web Application Firewall)                       │
│                    Rate limiting, SQL injection protection                   │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Application Load Balancer (Public)                        │
│                 hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com         │
│                                                                              │
│   /api/*, /health, /v1/*  ──►  API Service (port 3000)                      │
│   /ws/*, /socket.io/*     ──►  WebSocket Service (port 3001)                │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
          ▼                       ▼                       ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│   hana-dev-api  │   │   hana-dev-ws   │   │ hana-dev-workers│
│    (Fargate)    │   │    (Fargate)    │   │    (Fargate)    │
│   Port: 3000    │   │   Port: 3001    │   │   Background    │
│   REST API      │   │   WebSockets    │   │   Job Queue     │
└────────┬────────┘   └────────┬────────┘   └────────┬────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  RDS PostgreSQL │   │ ElastiCache     │   │   SQS FIFO      │
│    (Private)    │   │ Redis (Private) │   │   Queue         │
│   Port: 5432    │   │   Port: 6379    │   │  agent-runs     │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

## Deployed Resources

### Stacks

| Stack                    | Status          | Description                                |
| ------------------------ | --------------- | ------------------------------------------ |
| `hana-dev-network`       | CREATE_COMPLETE | VPC, subnets, NAT gateway, security groups |
| `hana-dev-storage`       | CREATE_COMPLETE | ECR repository, S3 buckets                 |
| `hana-dev-secrets`       | CREATE_COMPLETE | Secrets Manager (API keys, DB credentials) |
| `hana-dev-messaging`     | CREATE_COMPLETE | SQS FIFO queues for agent runs             |
| `hana-dev-database`      | CREATE_COMPLETE | RDS PostgreSQL 16, ElastiCache Redis 7     |
| `hana-dev-iam`           | CREATE_COMPLETE | IAM roles for ECS, Lambda                  |
| `hana-dev-compute`       | CREATE_COMPLETE | ECS cluster, ALB, Fargate services         |
| `hana-dev-waf`           | CREATE_COMPLETE | WAF WebACL with rate limiting              |
| `hana-dev-observability` | CREATE_COMPLETE | CloudWatch dashboard, alarms               |

### Key Endpoints

| Resource          | Endpoint                                                            |
| ----------------- | ------------------------------------------------------------------- |
| **Load Balancer** | `hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com`               |
| **Health Check**  | `http://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/health` |
| **API**           | `http://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/api/`   |
| **WebSocket**     | `ws://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/ws/`      |

### Internal Resources (Private Subnets)

| Resource           | Endpoint                                                          | Notes                          |
| ------------------ | ----------------------------------------------------------------- | ------------------------------ |
| **RDS PostgreSQL** | `hana-dev-postgres.cbwiy84ie3v1.us-east-1.rds.amazonaws.com:5432` | Only accessible from ECS tasks |
| **Redis**          | `master.hana-dev-redis.s0fepw.use1.cache.amazonaws.com:6379`      | Only accessible from ECS tasks |
| **ECR**            | `971422716287.dkr.ecr.us-east-1.amazonaws.com/hana-dev/api`       | Docker image repository        |

### AWS Console Links

- [CloudWatch Dashboard](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=hana-dev-overview)
- [ECS Cluster](https://us-east-1.console.aws.amazon.com/ecs/v2/clusters/hana-dev/services?region=us-east-1)
- [RDS Database](https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#database:id=hana-dev-postgres)
- [Secrets Manager](https://us-east-1.console.aws.amazon.com/secretsmanager/listsecrets?region=us-east-1&search=hana%2Fdev)
- [CloudFormation Stacks](https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks?filteringText=hana-dev)

---

## Gateway Authentication (Trusted Proxy Mode)

When deploying Hana behind an AWS ALB (or other identity-aware reverse proxy), use **trusted-proxy** auth mode. This allows the ALB to handle authentication and pass user identity via headers.

### Configuration

Add to your `~/.openclaw/config.yaml` or environment-specific config:

```yaml
gateway:
  auth:
    mode: trusted-proxy
    trustedProxy:
      # Header containing authenticated user identity (set by ALB/proxy)
      userHeader: x-forwarded-user
      # Additional headers that MUST be present to trust the request
      requiredHeaders:
        - x-forwarded-proto
        - x-forwarded-host
      # Optional: restrict to specific users (empty = allow all authenticated users)
      allowUsers: []
  # CIDR ranges of trusted proxies (ALB internal IPs)
  trustedProxies:
    - "10.0.0.0/16" # VPC CIDR
```

### Environment Variables

Alternatively, configure via environment:

```bash
OPENCLAW_GATEWAY_AUTH_MODE=trusted-proxy
OPENCLAW_GATEWAY_TRUSTED_PROXY_USER_HEADER=x-forwarded-user
```

### How It Works

1. ALB authenticates the user (via Cognito, OIDC, etc.)
2. ALB adds `x-forwarded-user` header with authenticated user identity
3. Hana validates the request came from a trusted proxy (ALB IP in VPC CIDR)
4. Hana extracts user identity from the configured header

### Security Considerations

- **trustedProxies** MUST be configured to only include ALB/proxy IP ranges
- Requests from non-trusted IPs are rejected even with valid headers
- This prevents header spoofing from untrusted clients

---

## Accessing HANA

### Option 1: Via Load Balancer (Production)

Once the Docker image is deployed and services are running:

```bash
# Health check
curl http://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/health

# API endpoint
curl http://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/api/v1/status
```

### Option 2: HANA TUI (Terminal UI)

Connect to HANA via the terminal interface:

```bash
# Local development
pnpm tui

# Or connect to the deployed gateway
OPENCLAW_GATEWAY_URL=http://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com \
  pnpm tui
```

### Option 3: ECS Exec (Direct Container Access)

SSH into a running container for debugging:

```bash
# Get a running task ID
TASK_ID=$(aws ecs list-tasks --cluster hana-dev --service-name hana-dev-api \
  --profile my-dev-profile --query 'taskArns[0]' --output text | cut -d'/' -f3)

# Connect to the container
aws ecs execute-command \
  --cluster hana-dev \
  --task $TASK_ID \
  --container api \
  --interactive \
  --command "/bin/sh" \
  --profile my-dev-profile
```

### Option 4: Database Access

Connect to PostgreSQL from within a container:

```bash
# First, exec into a container (see Option 3)
# Then connect to the database:
psql -h $DB_HOST -U $DB_USERNAME -d hana
```

---

## Deployment Commands

### AWS SSO Login

```bash
# Login to AWS SSO (required before any AWS operations)
pnpm aws:login
```

### Infrastructure Management

```bash
# Check stack status
pnpm aws:status

# Deploy all stacks
pnpm aws:deploy

# Deploy specific stack
pnpm aws:deploy:stack network
pnpm aws:deploy:stack database
pnpm aws:deploy:stack compute

# Delete all stacks (with confirmation)
pnpm aws:delete
```

### Application Deployment

```bash
# Build and push Docker image to ECR
pnpm aws:push

# Scale up services (after pushing image)
aws ecs update-service --cluster hana-dev --service hana-dev-api --desired-count 1 --profile my-dev-profile
aws ecs update-service --cluster hana-dev --service hana-dev-ws --desired-count 1 --profile my-dev-profile
aws ecs update-service --cluster hana-dev --service hana-dev-workers --desired-count 1 --profile my-dev-profile
```

### Logs

```bash
# Tail API logs
pnpm aws:logs

# Tail WebSocket logs
pnpm aws:logs:ws

# Tail Worker logs
pnpm aws:logs:workers

# Or use AWS CLI directly
aws logs tail /ecs/hana-dev/api --follow --profile my-dev-profile
```

---

## Secrets Configuration

After deployment, update the API keys in Secrets Manager:

```bash
# Anthropic API Key (REQUIRED)
aws secretsmanager put-secret-value \
  --secret-id hana/dev/anthropic-api-key \
  --secret-string '{"api_key": "sk-ant-api03-YOUR-KEY-HERE"}' \
  --profile my-dev-profile

# OpenAI API Key (optional)
aws secretsmanager put-secret-value \
  --secret-id hana/dev/openai-api-key \
  --secret-string '{"api_key": "sk-YOUR-KEY-HERE"}' \
  --profile my-dev-profile

# ElevenLabs API Key (optional, for voice)
aws secretsmanager put-secret-value \
  --secret-id hana/dev/elevenlabs-api-key \
  --secret-string '{"api_key": "YOUR-KEY-HERE"}' \
  --profile my-dev-profile
```

### View Current Secrets

```bash
# List all HANA secrets
aws secretsmanager list-secrets --filter Key=name,Values=hana/dev \
  --profile my-dev-profile --query 'SecretList[].Name'

# Get a secret value
aws secretsmanager get-secret-value \
  --secret-id hana/dev/rds-master \
  --profile my-dev-profile \
  --query 'SecretString' --output text | jq
```

---

## AWS Pricing Estimate

### Development Environment (Current)

| Service                       | Resource         | Specs                              | Monthly Cost    |
| ----------------------------- | ---------------- | ---------------------------------- | --------------- |
| **RDS PostgreSQL**            | db.t4g.medium    | 2 vCPU, 4 GB RAM, 20 GB storage    | ~$50            |
| **ElastiCache Redis**         | cache.t4g.medium | 2 vCPU, 3.09 GB RAM                | ~$47            |
| **ECS Fargate**               | 3 services       | 0.5 vCPU, 1 GB each (when running) | ~$55            |
| **NAT Gateway**               | 1 gateway        | Data processing                    | ~$35            |
| **Application Load Balancer** | 1 ALB            | + LCU charges                      | ~$22            |
| **VPC Endpoints**             | 4 endpoints      | ECR, Logs, Secrets Manager         | ~$30            |
| **S3**                        | 3 buckets        | Minimal storage                    | ~$1             |
| **CloudWatch**                | Logs + Metrics   | 7-day retention                    | ~$10            |
| **Secrets Manager**           | 7 secrets        |                                    | ~$3             |
| **SQS**                       | 3 queues         | FIFO + standard                    | ~$1             |
| **WAF**                       | WebACL           | + request charges                  | ~$6             |
|                               |                  |                                    |                 |
| **TOTAL**                     |                  |                                    | **~$260/month** |

### Production Environment (Recommended)

| Service                       | Resource                  | Specs                        | Monthly Cost    |
| ----------------------------- | ------------------------- | ---------------------------- | --------------- |
| **RDS PostgreSQL**            | db.r6g.large Multi-AZ     | 2 vCPU, 16 GB RAM, 100 GB    | ~$300           |
| **ElastiCache Redis**         | cache.r6g.large + replica | 2 vCPU, 13 GB RAM x2         | ~$200           |
| **ECS Fargate**               | 3 services                | 1 vCPU, 2 GB each, 2-4 tasks | ~$200           |
| **NAT Gateway**               | 2 gateways (HA)           | Data processing              | ~$70            |
| **Application Load Balancer** | 1 ALB                     | + LCU charges                | ~$30            |
| **VPC Endpoints**             | 4 endpoints               |                              | ~$30            |
| **S3**                        | 3 buckets                 | ~100 GB storage              | ~$5             |
| **CloudWatch**                | Logs + Metrics            | 30-day retention             | ~$30            |
| **Secrets Manager**           | 7 secrets                 |                              | ~$3             |
| **SQS**                       | 3 queues                  |                              | ~$2             |
| **WAF**                       | WebACL                    |                              | ~$10            |
| **Route 53**                  | Hosted zone               |                              | ~$1             |
| **ACM**                       | SSL Certificate           |                              | Free            |
|                               |                           |                              |                 |
| **TOTAL**                     |                           |                              | **~$880/month** |

### Cost Optimization Tips

1. **Use Reserved Instances** for RDS (up to 60% savings)
2. **Use Fargate Spot** for workers (up to 70% savings)
3. **Enable S3 Intelligent-Tiering** for media storage
4. **Set CloudWatch Logs retention** to minimum needed
5. **Stop dev environment** when not in use:
   ```bash
   # Scale down all services
   aws ecs update-service --cluster hana-dev --service hana-dev-api --desired-count 0 --profile my-dev-profile
   aws ecs update-service --cluster hana-dev --service hana-dev-ws --desired-count 0 --profile my-dev-profile
   aws ecs update-service --cluster hana-dev --service hana-dev-workers --desired-count 0 --profile my-dev-profile
   ```

### Free Tier Eligible

Some resources may be covered by AWS Free Tier (first 12 months):

- 750 hours/month of t2.micro or t3.micro RDS
- 750 hours/month of cache.t2.micro or cache.t3.micro ElastiCache
- 5 GB S3 storage
- 1 million SQS requests

---

## Network Architecture

### VPC CIDR: 10.0.0.0/16

| Subnet Type  | AZ-a        | AZ-b        | Purpose          |
| ------------ | ----------- | ----------- | ---------------- |
| **Public**   | 10.0.0.0/24 | 10.0.1.0/24 | ALB, NAT Gateway |
| **Private**  | 10.0.2.0/24 | 10.0.3.0/24 | ECS Tasks        |
| **Database** | 10.0.4.0/24 | 10.0.5.0/24 | RDS, ElastiCache |

### Security Groups

| Security Group      | Inbound    | From      |
| ------------------- | ---------- | --------- |
| `hana-dev-alb-sg`   | 80, 443    | 0.0.0.0/0 |
| `hana-dev-ecs-sg`   | 3000, 3001 | ALB SG    |
| `hana-dev-rds-sg`   | 5432       | ECS SG    |
| `hana-dev-redis-sg` | 6379       | ECS SG    |

### VPC Endpoints (Cost Optimization)

Private endpoints to avoid NAT Gateway charges for AWS services:

- `com.amazonaws.us-east-1.ecr.api`
- `com.amazonaws.us-east-1.ecr.dkr`
- `com.amazonaws.us-east-1.logs`
- `com.amazonaws.us-east-1.secretsmanager`
- `com.amazonaws.us-east-1.s3` (Gateway)

---

## Monitoring & Alerts

### CloudWatch Dashboard

Access the dashboard: [hana-dev-overview](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=hana-dev-overview)

Widgets:

- ECS Service CPU/Memory
- ALB Request Count & Response Time
- RDS CPU & Connections
- Redis Memory Usage
- SQS Queue Depth
- Recent Errors (Log Insights)

### Configured Alarms

| Alarm             | Threshold        | Action           |
| ----------------- | ---------------- | ---------------- |
| API CPU High      | > 80% for 10 min | SNS notification |
| API Memory High   | > 85% for 10 min | SNS notification |
| RDS CPU High      | > 80% for 10 min | SNS notification |
| RDS Storage Low   | < 5 GB           | SNS notification |
| Redis Memory High | > 80%            | SNS notification |
| ALB 5xx Errors    | > 10 in 5 min    | SNS notification |
| DLQ Messages      | >= 1             | SNS notification |

### Enable Alarm Notifications

```bash
# Subscribe email to alarms
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:971422716287:hana-dev-alarms \
  --protocol email \
  --notification-endpoint your@email.com \
  --profile my-dev-profile
```

---

## Troubleshooting

### Services Not Starting

```bash
# Check service events
aws ecs describe-services --cluster hana-dev --services hana-dev-api \
  --profile my-dev-profile --query 'services[0].events[0:5]'

# Check task failures
aws ecs list-tasks --cluster hana-dev --desired-status STOPPED \
  --profile my-dev-profile

# Get task details
aws ecs describe-tasks --cluster hana-dev --tasks <task-arn> \
  --profile my-dev-profile --query 'tasks[0].stoppedReason'
```

### Container Logs

```bash
# Real-time logs
aws logs tail /ecs/hana-dev/api --follow --profile my-dev-profile

# Filter for errors
aws logs tail /ecs/hana-dev/api --filter-pattern "ERROR" --profile my-dev-profile

# Logs from last hour
aws logs tail /ecs/hana-dev/api --since 1h --profile my-dev-profile
```

### Database Connection

```bash
# Test from container
aws ecs execute-command --cluster hana-dev --task <task-id> --container api \
  --interactive --command "nc -zv \$DB_HOST 5432" --profile my-dev-profile
```

### Common Issues

| Issue                    | Cause            | Solution                          |
| ------------------------ | ---------------- | --------------------------------- |
| Tasks keep restarting    | Missing secrets  | Update secrets in Secrets Manager |
| Health check failing     | App not starting | Check container logs              |
| Cannot pull image        | No image in ECR  | Run `pnpm aws:push`               |
| Database timeout         | Security group   | Check RDS SG allows ECS SG        |
| Redis connection refused | AUTH token       | Verify redis-auth secret          |

---

## File Structure

```
cloudformation/
├── README.md           # CloudFormation documentation
├── deploy.sh           # Deployment script (SSO-enabled)
├── network.yaml        # VPC, subnets, NAT, security groups
├── storage.yaml        # ECR, S3 buckets
├── secrets.yaml        # Secrets Manager
├── messaging.yaml      # SQS queues
├── database.yaml       # RDS PostgreSQL, ElastiCache Redis
├── iam.yaml            # IAM roles
├── compute.yaml        # ECS cluster, ALB, services
├── waf.yaml            # WAF WebACL
├── observability.yaml  # CloudWatch, alarms
└── main.yaml           # Master stack (nested)

scripts/
└── deploy-aws.sh       # Docker build & push script
```

---

## Quick Reference

```bash
# Login
pnpm aws:login

# Deploy infrastructure
pnpm aws:deploy

# Push Docker image
pnpm aws:push

# Scale up
aws ecs update-service --cluster hana-dev --service hana-dev-api --desired-count 1 --profile my-dev-profile

# Check health
curl http://hana-dev-alb-1655690598.us-east-1.elb.amazonaws.com/health

# View logs
pnpm aws:logs

# Check status
pnpm aws:status
```

---

## Webchat Embedding

Hana can be embedded as a webchat widget in external websites (e.g., Hom Next.js website) using trusted-proxy authentication. This allows the hosting website to authenticate users and pass their identity to Hana via HTTP headers.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Hom Next.js Website                                │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        HanaWidget (React)                            │   │
│   │   - Establishes WebSocket connection to /ws/chat                    │   │
│   │   - Sends chat.send messages                                        │   │
│   │   - Receives chat.history and streaming responses                   │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────┬────────────────────────────────────────┘
                                     │
                                     │ WebSocket + X-Forwarded-User header
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Application Load Balancer (ALB)                           │
│   - Routes /ws/* to WebSocket target group                                  │
│   - Preserves X-Forwarded-User header from trusted origins                  │
│   - Enables WebSocket stickiness via lb_cookie                              │
└────────────────────────────────────┬────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Hana Gateway (ECS Fargate)                           │
│   - Validates X-Forwarded-User header from trusted proxies                  │
│   - Creates/resumes sessions per user                                       │
│   - Streams AI responses back via WebSocket                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Trusted-Proxy Authentication Setup

Trusted-proxy auth allows the ALB (or any upstream proxy) to assert user identity via headers. Hana validates that the request originated from a configured trusted proxy IP before accepting the user header.

#### 1. Configure Trusted Proxies

Update `openclaw.config.yaml` (or use environment variables) to enable trusted-proxy auth:

```yaml
gateway:
  auth:
    mode: trusted-proxy
    trustedProxy:
      userHeader: x-forwarded-user # Header containing authenticated user ID
      requiredHeaders: # Optional: additional required headers
        - x-forwarded-proto
      allowUsers: [] # Empty = allow all users, or specify allowlist
  trustedProxies:
    - 10.0.0.0/24 # ALB private subnet 1
    - 10.0.1.0/24 # ALB private subnet 2
```

#### 2. Environment Variables

Alternatively, configure via environment variables:

```bash
# In ECS task definition or Secrets Manager
OPENCLAW_GATEWAY_AUTH_MODE=trusted-proxy
OPENCLAW_GATEWAY_TRUSTED_PROXY_USER_HEADER=x-forwarded-user
```

#### 3. ALB Configuration

The ALB must forward the `X-Forwarded-User` header from the upstream application. The CloudFormation template (`cloudformation/compute.yaml`) includes:

- WebSocket target group with sticky sessions (`lb_cookie`)
- Listener rules that route `/ws/*` to the WebSocket service
- Header passthrough for trusted proxy authentication

#### 4. Security Considerations

- **Trusted Proxies Only**: Hana only accepts the `X-Forwarded-User` header from IPs listed in `trustedProxies`. Requests from other sources will be rejected.
- **Header Validation**: The ALB/proxy must set `X-Forwarded-User` only after authenticating the end user.
- **HTTPS Required**: In production, ensure all traffic between the website and ALB uses HTTPS.
- **CORS**: Configure CORS headers if the webchat widget runs on a different domain.

### WebSocket Protocol

The webchat widget communicates with Hana using JSON messages over WebSocket:

#### Connect

```javascript
const ws = new WebSocket("wss://hana-dev-alb.../ws/chat");
```

#### Request Chat History

```json
{
  "type": "chat.history",
  "id": "req-1",
  "params": {
    "sessionKey": "user@example.com",
    "limit": 100
  }
}
```

#### Send Message

```json
{
  "type": "chat.send",
  "id": "req-2",
  "params": {
    "sessionKey": "user@example.com",
    "message": "Hello, Hana!",
    "idempotencyKey": "msg-uuid-123"
  }
}
```

#### Receive Streaming Response

Hana broadcasts `chat` events with streaming deltas:

```json
{
  "type": "chat",
  "payload": {
    "runId": "run-123",
    "sessionKey": "user@example.com",
    "seq": 1,
    "state": "delta",
    "text": "Hello! "
  }
}
```

Final message includes the complete assistant response:

```json
{
  "type": "chat",
  "payload": {
    "runId": "run-123",
    "sessionKey": "user@example.com",
    "seq": 10,
    "state": "final",
    "message": {
      "role": "assistant",
      "content": [{ "type": "text", "text": "Hello! How can I help you today?" }],
      "timestamp": 1708000000000
    }
  }
}
```

### Embed Instructions

See [WEBCHAT.md](./WEBCHAT.md) for detailed embedding instructions and the React widget code.
