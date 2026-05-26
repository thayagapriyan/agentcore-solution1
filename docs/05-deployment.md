# 05 — Deployment

End-to-end deploy: build the ARM64 image, push to ECR, apply Terraform, invoke the agent.

---

## Pre-flight check

```bash
# Sanity-check everything from doc 01
node -v && docker buildx version && aws sts get-caller-identity && terraform -v
```

Set shell vars used below:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export AGENT_NAME=inventory-agent
export ECR_URI=${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${AGENT_NAME}
```

On PowerShell:

```powershell
$env:AWS_REGION = "us-east-1"
$env:AWS_ACCOUNT = (aws sts get-caller-identity --query Account --output text)
$env:AGENT_NAME = "inventory-agent"
$env:ECR_URI = "$($env:AWS_ACCOUNT).dkr.ecr.$($env:AWS_REGION).amazonaws.com/$($env:AGENT_NAME)"
```

---

## Step 1 — Provision ECR + IAM (Terraform, partial apply)

```bash
cd infra
terraform init
terraform apply \
  -target=aws_ecr_repository.agent \
  -target=aws_iam_role.agent_runtime \
  -auto-approve
```

This creates the ECR repo so we can push to it. The Runtime resource needs the image to exist before it can pull, hence the two-phase apply.

---

## Step 2 — Build the ARM64 image

```bash
cd ..    # back to project root

docker buildx build \
  --platform linux/arm64 \
  --tag ${ECR_URI}:latest \
  --tag ${ECR_URI}:$(git rev-parse --short HEAD) \
  --load \
  .
```

> On Windows/x86, buildx uses QEMU to cross-compile. First build is slow (~3–5 min); subsequent builds use cache and finish in ~30s.

Verify it runs locally:

```bash
docker run --rm -p 8080:8080 \
  -e AWS_REGION=${AWS_REGION} \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  ${ECR_URI}:latest

# In another terminal
curl http://localhost:8080/ping
# → {"status":"ok"}
```

---

## Step 3 — Push to ECR

```bash
aws ecr get-login-password --region ${AWS_REGION} \
  | docker login --username AWS --password-stdin ${ECR_URI}

docker push ${ECR_URI}:latest
docker push ${ECR_URI}:$(git rev-parse --short HEAD)
```

Confirm:

```bash
aws ecr describe-images --repository-name ${AGENT_NAME} \
  --query 'imageDetails[].imageTags' --output table
```

---

## Step 4 — Apply the rest of Terraform

```bash
cd infra
terraform apply -auto-approve
```

Capture the outputs:

```bash
export AGENT_RUNTIME_ARN=$(terraform output -raw agent_runtime_arn)
echo $AGENT_RUNTIME_ARN
```

---

## Step 5 — Invoke

### Via AWS CLI

```bash
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn $AGENT_RUNTIME_ARN \
  --payload '{"prompt": "How many SKU-123 in stock?"}' \
  --region $AWS_REGION \
  response.json

cat response.json
```

### Via SDK (TypeScript)

```typescript
import { BedrockAgentCoreClient, InvokeAgentRuntimeCommand } from
  "@aws-sdk/client-bedrock-agentcore";

const client = new BedrockAgentCoreClient({ region: "us-east-1" });

const response = await client.send(new InvokeAgentRuntimeCommand({
  agentRuntimeArn: process.env.AGENT_RUNTIME_ARN,
  payload: new TextEncoder().encode(JSON.stringify({
    prompt: "How many SKU-123 in stock?",
    sessionId: "session-001",
  })),
}));

const body = JSON.parse(new TextDecoder().decode(response.payload));
console.log(body.result);
```

---

## Step 6 — Verify

### Logs

```bash
aws logs tail /aws/bedrock-agentcore/${AGENT_NAME} --follow --region ${AWS_REGION}
```

### Traces

Open CloudWatch → **Application Signals** → **Service map**. Each invocation produces a trace with spans for `/invocations`, `bedrock:InvokeModel`, and any tool calls.

### Metrics

CloudWatch → **Metrics** → **AWS/BedrockAgentCore**:

- `InvocationCount`
- `InvocationLatency` (p50, p99)
- `InvocationErrors`
- `InputTokens` / `OutputTokens`

---

## Updating the agent

After code changes:

```bash
# Build + tag with new SHA
TAG=$(git rev-parse --short HEAD)
docker buildx build --platform linux/arm64 -t ${ECR_URI}:${TAG} --load .
docker push ${ECR_URI}:${TAG}

# Roll the runtime to the new image
cd infra
terraform apply -var="image_tag=${TAG}" -auto-approve
```

Runtimes do a rolling update — no downtime, in-flight sessions complete on the old version, new sessions go to the new image.

---

## Rollback

```bash
# Find a known-good tag
aws ecr describe-images --repository-name ${AGENT_NAME} \
  --query 'imageDetails[].[imagePushedAt, imageTags[0]]' --output table

# Re-apply with that tag
cd infra
terraform apply -var="image_tag=<KNOWN_GOOD_SHA>" -auto-approve
```

---

## CI/CD — GitHub Actions skeleton

`.github/workflows/deploy.yml`:

```yaml
name: Deploy AgentCore

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Set up buildx
        uses: docker/setup-buildx-action@v3

      - name: ECR login
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build & push (ARM64)
        env:
          ECR_URI: ${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}
        run: |
          docker buildx build \
            --platform linux/arm64 \
            --push \
            -t $ECR_URI:${{ github.sha }} \
            -t $ECR_URI:latest \
            .

      - uses: hashicorp/setup-terraform@v3
        with: { terraform_version: 1.6.6 }

      - name: Terraform apply
        working-directory: infra
        run: |
          terraform init
          terraform apply -auto-approve -var="image_tag=${{ github.sha }}"

      - name: Smoke test
        run: |
          ARN=$(cd infra && terraform output -raw agent_runtime_arn)
          aws bedrock-agentcore invoke-agent-runtime \
            --agent-runtime-arn $ARN \
            --payload '{"prompt":"ping"}' \
            smoke.json
          grep -q result smoke.json
```

---

## Common deploy errors

| Error | Cause | Fix |
|-------|-------|-----|
| `exec format error` in logs | Pushed amd64 image | Re-build with `--platform linux/arm64` |
| Runtime stuck in `CREATING` | IAM role can't pull from ECR | Check `ecr_pull` policy + trust policy |
| `/ping` health check fails | Container not listening on 8080 | Verify `PORT=8080` env + `0.0.0.0` bind |
| `AccessDeniedException` on Bedrock | Model access not granted | Bedrock console → Model access |
| `InvalidRequestException: image not found` | Pushed to wrong region | `ECR_URI` region must match runtime region |

Next: [06-migration.md](06-migration.md) — migrating an existing Bedrock Agents project.
