# Bedrock AgentCore Deployment Guide

End-to-end guide for deploying an AI agent project to **Amazon Bedrock AgentCore Runtime** using TypeScript, Node.js, Strands SDK, and Terraform.

This documentation set is designed to be reusable — apply it to this `agentcore-solution1` project or any new agent project.

---

## What is AgentCore?

Amazon Bedrock **AgentCore** is the AWS-managed runtime for hosting AI agents as long-running containers. It replaces the older Bedrock Agents (action-group + Lambda) pattern with a code-first model where you ship your own agent (Strands, LangGraph, custom) as an OCI image and AWS handles sessions, identity, memory, observability, and tool routing.

| Concern | Legacy Bedrock Agents | **Bedrock AgentCore** |
|---|---|---|
| Hosting | Lambda + action groups | Container on managed runtime |
| Agent framework | AWS-prescribed orchestration | Bring your own (Strands, LangGraph, etc.) |
| Sessions | Stateless | Built-in session + memory |
| Tools | Action groups | MCP via AgentCore Gateway |
| Identity | IAM only | OAuth, Cognito, IAM |
| Observability | CloudWatch logs | Traces + spans + metrics |
| Packaging | Lambda zip | OCI container image (ARM64) |

---

## Reading order

| # | Doc | What it covers |
|---|-----|----------------|
| 1 | [01-prerequisites.md](01-prerequisites.md) | Tools, accounts, IAM, Bedrock model access |
| 2 | [02-architecture.md](02-architecture.md) | AgentCore Runtime, Gateway, Memory, Identity |
| 3 | [03-agent-code.md](03-agent-code.md) | TypeScript + Node.js + Strands entrypoint, Dockerfile |
| 4 | [04-terraform.md](04-terraform.md) | Full IaC reference (ECR, IAM, runtime, gateway) |
| 5 | [05-deployment.md](05-deployment.md) | Build → push → deploy → invoke |
| 6 | [06-migration.md](06-migration.md) | Migrating an existing Bedrock Agents project to AgentCore |
| ★ | [iteration-plan.md](iteration-plan.md) | **Build it step-by-step** — 12 small, additive iterations with Design / Develop / Test / Deploy phases |

---

## Quickstart (TL;DR)

```bash
# 1. Prereqs
aws configure
aws bedrock list-foundation-models --region us-east-1   # confirm model access

# 2. Build the agent container (ARM64 — AgentCore requirement)
docker buildx build --platform linux/arm64 -t my-agent:latest .

# 3. Push to ECR
aws ecr create-repository --repository-name my-agent
docker tag my-agent:latest <ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/my-agent:latest
docker push <ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/my-agent:latest

# 4. Deploy via Terraform
cd infra
terraform init && terraform apply

# 5. Invoke
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn <ARN> \
  --payload '{"prompt":"How many SKU-123 in stock?"}'
```

Full walkthrough in [05-deployment.md](05-deployment.md).

---

## Tech stack covered

- **TypeScript 5.x** — agent source
- **Node.js 20.x** — runtime (ARM64)
- **Strands Agents SDK** — agent framework
- **Express / Fastify** — HTTP entrypoint (port 8080)
- **Docker / buildx** — ARM64 containerization
- **Amazon ECR** — image registry
- **Terraform 1.6+** — IaC
- **Bedrock AgentCore Runtime** — managed agent host
- **AgentCore Gateway** — managed MCP endpoint
- **CloudWatch + X-Ray** — observability

---

## Repository layout this guide assumes

```
agentcore-solution1/
├── src/
│   ├── app.ts                  # HTTP entrypoint (port 8080)
│   ├── agent.ts                # Strands agent definition
│   └── tools/                  # Local MCP tools (if any)
├── infra/
│   ├── main.tf                 # ECR + runtime + gateway
│   ├── iam.tf                  # Execution role + policies
│   ├── variables.tf
│   └── outputs.tf
├── Dockerfile                  # ARM64 Node 20 image
├── package.json
├── tsconfig.json
└── docs/                       # this directory
```
