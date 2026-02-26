# HANA Infrastructure - What Changed and Why

This document explains the infrastructure changes introduced in commit `2ad7748ed` ("Hana infra"), which added complete AWS deployment capabilities to the HANA project.

## What Was Added

The commit introduced a production-ready AWS infrastructure setup using Infrastructure as Code (CloudFormation), including:

- **9 CloudFormation templates** for deploying HANA to AWS
- **Deployment automation scripts** for building, pushing, and managing the infrastructure
- **AWS integration scripts** for secrets management and service operations
- **24 new npm scripts** for simplified AWS operations
- **Complete documentation** for deployment and operations
- **Dockerfile updates** to support containerized deployment

## Why This Infrastructure Was Needed

### 1. Production Deployment Capability

Before this commit, HANA could only run locally or required manual deployment setup. This infrastructure provides:

- **One-command deployment** to AWS using battle-tested services
- **Scalable architecture** that can handle production workloads
- **Enterprise-grade security** with encryption, network isolation, and secrets management
- **High availability** with multi-AZ database and auto-scaling compute

### 2. Development-Production Parity

Running HANA in a cloud environment that mirrors production helps:

- **Test real-world scenarios** (networking, scaling, resource constraints)
- **Catch deployment issues early** before they affect production
- **Validate integration** with AWS services (RDS, Redis, S3, SQS)
- **Enable remote collaboration** with a shared development environment

### 3. Modern Cloud-Native Architecture

The infrastructure follows AWS best practices:

```
Internet → WAF → Load Balancer → Container Services (ECS Fargate)
                                         ↓
                          Database (RDS) + Cache (Redis) + Queue (SQS)
                                         ↓
                                    Storage (S3)
```

This architecture provides:

- **Automatic scaling** based on load
- **Zero-downtime deployments** with rolling updates
- **Built-in monitoring** with CloudWatch
- **Cost optimization** through right-sized resources

## Key Components

### Infrastructure Stacks (CloudFormation)

| Stack                  | Purpose                       | Why It's Needed                                 |
| ---------------------- | ----------------------------- | ----------------------------------------------- |
| **network.yaml**       | VPC, subnets, security groups | Network isolation, security boundaries          |
| **database.yaml**      | PostgreSQL + Redis            | Persistent storage, caching, session management |
| **compute.yaml**       | ECS Fargate services          | Containerized application runtime               |
| **storage.yaml**       | S3 buckets, ECR registry      | Media storage, Docker images                    |
| **secrets.yaml**       | Secrets Manager               | Secure API key storage (Anthropic, OpenAI)      |
| **messaging.yaml**     | SQS queues                    | Async job processing for agent runs             |
| **waf.yaml**           | Web Application Firewall      | DDoS protection, rate limiting                  |
| **observability.yaml** | CloudWatch dashboards         | Monitoring, alerting, debugging                 |
| **iam.yaml**           | IAM roles and policies        | Least-privilege access control                  |

### Deployment Scripts

```
scripts/
├── deploy-aws.sh     # Build Docker image, push to ECR, deploy to ECS
├── aws-secret.sh     # Manage API keys in Secrets Manager
└── npm-publish.mjs   # Publish packages (if needed)

cloudformation/
└── deploy.sh         # Deploy/update/delete CloudFormation stacks
```

### NPM Scripts Added

The commit added 24 npm scripts for managing AWS operations:

```bash
# Infrastructure Management
pnpm aws:login        # Login to AWS SSO
pnpm aws:deploy       # Deploy all CloudFormation stacks
pnpm aws:status       # Check stack status
pnpm aws:delete       # Delete all stacks

# Application Deployment
pnpm aws:push         # Build Docker image and deploy to dev
pnpm aws:push:prod    # Deploy to production
pnpm aws:restart      # Force service restart with new image

# Secrets Management
pnpm aws:secret:set   # Update API keys
pnpm aws:secret:get   # Retrieve secrets
pnpm aws:secret:list  # List all secrets

# Monitoring & Operations
pnpm aws:logs         # Tail API logs
pnpm aws:logs:ws      # Tail WebSocket logs
pnpm aws:services     # Show service status
pnpm aws:tui          # Connect to HANA TUI in container
```

## Architecture Highlights

### 1. Multi-Service Deployment

The infrastructure runs three separate services:

- **hana-dev-api**: REST API service (port 3000)
- **hana-dev-ws**: WebSocket service for real-time communication (port 3001)
- **hana-dev-workers**: Background job processing

This separation allows:

- Independent scaling of each service
- Better resource utilization
- Fault isolation (API failure doesn't affect WebSocket)

### 2. Network Security

```
Public Subnets (10.0.0.0/24, 10.0.1.0/24)
  └── Load Balancer only

Private Subnets (10.0.2.0/24, 10.0.3.0/24)
  └── ECS Tasks (application containers)

Database Subnets (10.0.4.0/24, 10.0.5.0/24)
  └── RDS, Redis (no internet access)
```

Benefits:

- Database never exposed to internet
- Application services isolated from public access
- Only load balancer accepts external traffic

### 3. Secrets Management

All sensitive credentials stored in AWS Secrets Manager:

- Anthropic API keys
- OpenAI API keys
- Database passwords
- Redis authentication tokens
- JWT signing keys

Containers fetch secrets at runtime (never committed to git).

### 4. Observability

CloudWatch dashboard tracks:

- Service CPU/Memory usage
- Request rates and response times
- Database connections and performance
- Queue depth and processing
- Error rates and logs

Alarms configured for:

- High CPU/Memory (>80%)
- Database storage low (<5GB)
- Error rate spikes (>10 errors/5min)
- Dead letter queue messages

## Dockerfile Changes

The commit modified the Dockerfile to support container health checks:

```diff
- CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
+ CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan"]
```

**Why?**

- AWS ECS health checks need to reach the container from outside
- `--bind lan` allows the load balancer to perform health checks
- Previously bound to localhost only (secure for local dev, but prevents health checks)

## Cost Structure

### Development Environment: ~$260/month

The infrastructure uses cost-optimized resources for development:

- **RDS PostgreSQL** (db.t4g.medium): ~$50/month
- **ElastiCache Redis** (cache.t4g.medium): ~$47/month
- **ECS Fargate** (3 services, 0.5 vCPU each): ~$55/month
- **NAT Gateway**: ~$35/month
- **Application Load Balancer**: ~$22/month
- **VPC Endpoints** (4 endpoints): ~$30/month
- **Other** (S3, CloudWatch, Secrets, SQS, WAF): ~$21/month

**Cost Optimization Tips:**

- Scale services to 0 when not in use
- Use t4g instances (ARM-based, cheaper than x86)
- VPC endpoints reduce NAT Gateway data charges
- 7-day log retention in development

### Production Environment: ~$880/month

Production uses larger, highly-available resources:

- Multi-AZ database
- Redis replicas
- Multiple NAT gateways for redundancy
- Auto-scaling (2-20 tasks)
- 30-day log retention

## How to Use

### Initial Setup

```bash
# 1. Login to AWS
pnpm aws:login

# 2. Deploy infrastructure (takes ~15 minutes)
pnpm aws:deploy

# 3. Set API keys
pnpm aws:secret:set

# 4. Build and deploy application
pnpm aws:push

# 5. Verify deployment
curl http://hana-dev-alb-XXXXXXX.us-east-1.elb.amazonaws.com/health
```

### Daily Operations

```bash
# View logs
pnpm aws:logs

# Check service status
pnpm aws:services

# Deploy code changes
pnpm aws:push

# Connect to HANA in container
pnpm aws:tui

# Scale down to save costs
aws ecs update-service --cluster hana-dev --service hana-dev-api --desired-count 0
```

## Why Each Technology Choice

### AWS ECS Fargate

**Why not EC2?**

- No server management (no patching, no SSH, no OS updates)
- Pay only for actual container runtime
- Auto-scaling built-in
- Better security (ephemeral containers)

**Why not Lambda?**

- HANA needs long-running WebSocket connections
- Lambda has 15-minute timeout
- Cold starts problematic for real-time AI
- Container gives full control over runtime

**Why not Kubernetes?**

- ECS simpler for single-team projects
- Lower operational overhead
- Better AWS integration
- Still containerized, still portable

### PostgreSQL (RDS)

**Why not DynamoDB?**

- HANA needs relational queries (joins, transactions)
- PostgreSQL better for structured agent data
- ACID guarantees for conversation history
- JSON support for flexible schemas

**Why managed (RDS) not self-hosted?**

- Automatic backups
- Automated patching
- Multi-AZ failover
- Point-in-time recovery
- Less operational burden

### Redis (ElastiCache)

**Why Redis?**

- Session caching for WebSocket connections
- Rate limiting state
- Real-time pub/sub for agent events
- Fast temporary storage (LRU eviction)

### SQS FIFO

**Why queues?**

- Agent runs can take minutes
- Decouple API from long-running tasks
- Retry failed jobs automatically
- Scale workers independently

**Why SQS over RabbitMQ/Redis?**

- Fully managed (no servers)
- Exactly-once delivery (FIFO)
- Deep CloudWatch integration
- Unlimited retention (up to 14 days)

### CloudFormation

**Why not Terraform?**

- Native AWS integration
- No state file management
- Built-in rollback on failure
- Free (no Terraform Cloud needed)
- Stack dependencies handled automatically

**Why Infrastructure as Code?**

- Reproducible deployments
- Version controlled infrastructure
- Easy to review changes (git diff)
- Disaster recovery (redeploy from code)
- Multi-environment (dev/staging/prod)

## Security Features

1. **Network Isolation**: Database in private subnets, no public IP
2. **Encryption at Rest**: RDS, Redis, S3, SQS all encrypted
3. **Encryption in Transit**: TLS for all connections
4. **Secrets Management**: No credentials in code or environment variables
5. **WAF Protection**: Rate limiting, SQL injection prevention, OWASP rules
6. **IAM Least Privilege**: Each service has minimal required permissions
7. **VPC Endpoints**: AWS API calls stay within AWS network
8. **Security Groups**: Whitelist-only network access

## Migration Path

This infrastructure provides a foundation for future improvements:

1. **Add HTTPS**: Register domain, configure ACM certificate, update ALB
2. **Add CDN**: CloudFront for static assets, global distribution
3. **Multi-Region**: Deploy to multiple AWS regions for redundancy
4. **Autoscaling**: Add CPU/memory-based scaling policies
5. **CI/CD**: GitHub Actions to auto-deploy on merge
6. **Blue/Green Deployments**: Zero-downtime releases
7. **Spot Instances**: Use Fargate Spot for 70% cost savings on workers

## Files Overview

```
cloudformation/
├── README.md              # CloudFormation-specific docs
├── deploy.sh              # Stack deployment script
├── main.yaml              # Master stack (orchestrator)
├── network.yaml           # 488 lines - VPC, subnets, security
├── compute.yaml           # 697 lines - ECS, ALB, services
├── database.yaml          # 253 lines - RDS, Redis
├── storage.yaml           # 209 lines - ECR, S3
├── secrets.yaml           # 151 lines - API keys, credentials
├── messaging.yaml         # 157 lines - SQS queues
├── iam.yaml               # 221 lines - IAM roles, policies
├── waf.yaml               # 201 lines - WAF rules
└── observability.yaml     # 349 lines - CloudWatch, alarms

scripts/
├── deploy-aws.sh          # 250 lines - Docker build/push
├── aws-secret.sh          # 105 lines - Secrets helper
└── npm-publish.mjs        # 72 lines - Package publishing

INFRASTRUCTURE.md          # 480 lines - Complete operations guide
```

**Total:** 4,598 lines of infrastructure code and documentation

## Summary

This infrastructure commit transforms HANA from a local development tool to a production-ready cloud application. It provides:

- **Scalability**: Handle thousands of concurrent users
- **Reliability**: Multi-AZ databases, auto-healing containers
- **Security**: Network isolation, encryption, secrets management
- **Observability**: Comprehensive monitoring and alerting
- **Cost-Efficiency**: Right-sized resources, auto-scaling
- **Developer Experience**: One-command deployment, simple operations

The infrastructure is designed to be:

- **Easy to deploy**: `pnpm aws:deploy`
- **Easy to operate**: Automated monitoring and alerting
- **Easy to understand**: Comprehensive documentation
- **Easy to modify**: Infrastructure as code, modular stacks
- **Easy to delete**: `pnpm aws:delete` (for cost control)

For detailed operational procedures, see [INFRASTRUCTURE.md](./INFRASTRUCTURE.md).
For CloudFormation specifics, see [cloudformation/README.md](./cloudformation/README.md).
