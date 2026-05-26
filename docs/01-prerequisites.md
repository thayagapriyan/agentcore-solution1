# 01 — Prerequisites

Everything you need installed, configured, and enabled before deploying to Bedrock AgentCore.

---

## Local tools

| Tool | Version | Purpose | Install check |
|------|---------|---------|---------------|
| **Node.js** | 20.x LTS | Runtime for agent + build | `node -v` |
| **npm** | 10.x | Package manager | `npm -v` |
| **TypeScript** | 5.4+ | Source language | `npx tsc -v` |
| **Docker** | 24+ with buildx | ARM64 image builds | `docker buildx version` |
| **AWS CLI** | v2.15+ | Deploy + invoke | `aws --version` |
| **Terraform** | 1.6+ | IaC | `terraform -v` |
| **Git** | 2.40+ | Source control | `git --version` |

> **Why ARM64?** AgentCore Runtime accepts `linux/arm64` images only. On Windows/x86 machines, Docker buildx with QEMU handles the cross-build.

Enable buildx (one time):

```bash
docker buildx create --use --name agentcore-builder
docker buildx inspect --bootstrap
```

---

## AWS account setup

### 1. IAM user/role for deployment

Your deploy identity needs these managed policies (or scoped equivalents):

- `AmazonBedrockFullAccess`
- `AmazonEC2ContainerRegistryFullAccess`
- `IAMFullAccess` (only for `terraform apply` — restrict in CI)
- `CloudWatchLogsFullAccess`

```bash
aws configure
# Region: us-east-1 (or us-west-2 — AgentCore availability)
```

### 2. Enable Bedrock model access

In the Bedrock console → **Model access** → request access to:

- `anthropic.claude-3-5-sonnet-20241022-v2:0` (recommended for agents)
- `anthropic.claude-3-5-haiku-20241022-v1:0` (cheaper option)

Verify:

```bash
aws bedrock list-foundation-models \
  --region us-east-1 \
  --query "modelSummaries[?contains(modelId,'claude-3-5')].modelId"
```

### 3. AgentCore service availability

AgentCore is currently in regions: `us-east-1`, `us-west-2`, `eu-west-1`, `ap-southeast-2`. Confirm with:

```bash
aws bedrock-agentcore-control list-agent-runtimes --region us-east-1
```

A successful empty list (`{ "agentRuntimes": [] }`) confirms access.

---

## NPM packages (agent project)

```bash
npm init -y
npm i \
  @aws/strands-agents \
  @modelcontextprotocol/sdk \
  express \
  @aws-sdk/client-bedrock-runtime \
  zod

npm i -D \
  typescript \
  @types/node \
  @types/express \
  tsx
```

`package.json` scripts:

```json
{
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/app.js",
    "dev": "tsx watch src/app.ts"
  }
}
```

`tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
```

---

## AgentCore Runtime contract

Your container **must**:

1. Listen on **port 8080** (HTTP)
2. Expose `POST /invocations` — receives `{ prompt, sessionId, ... }`, returns JSON
3. Expose `GET /ping` — returns `200 OK` for health checks
4. Be built for `linux/arm64`
5. Run as non-root (recommended)
6. Stay under **30 GB** image size and **8 GB** memory at runtime

These are validated when you create the runtime. Details and code in [03-agent-code.md](03-agent-code.md).

---

## GitHub repository secrets (for CI)

If deploying via GitHub Actions, set:

| Name | Kind | Notes |
|------|------|-------|
| `AWS_ROLE_ARN` | Variable | OIDC-assumed role (preferred over keys) |
| `AWS_REGION` | Variable | e.g. `us-east-1` |
| `ECR_REPOSITORY` | Variable | e.g. `inventory-agent` |
| `TF_STATE_BUCKET` | Variable | Backend bucket |
| `TF_STATE_LOCK_TABLE` | Variable | DynamoDB lock table |

OIDC trust policy snippet:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::<ACCOUNT>:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike": { "token.actions.githubusercontent.com:sub": "repo:<ORG>/<REPO>:*" }
  }
}
```

---

## Verification checklist

Run all of these — every command should succeed before you continue:

```bash
node -v                                                    # v20.x
docker buildx version                                      # 0.12+
aws sts get-caller-identity                                # your account
aws bedrock list-foundation-models --region us-east-1      # non-empty
aws bedrock-agentcore-control list-agent-runtimes \
  --region us-east-1                                       # empty or list
terraform -v                                               # 1.6+
```

Next: [02-architecture.md](02-architecture.md).
