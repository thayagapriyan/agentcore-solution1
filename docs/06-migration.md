# 06 — Migrating from Bedrock Agents to AgentCore

Step-by-step migration from a legacy Bedrock Agents project (Lambda + action groups) to AgentCore Runtime. Uses the sibling `strands-solution1` project as the reference example.

---

## Where the legacy project stands

The sibling [strands-solution1](../../strands-solution1) project has:

- **Layer 1**: `inventory-api` Lambda → DynamoDB
- **Layer 2**: `mcp-server` (stdio MCP, spawned as subprocess)
- **Layer 3**: `agent` Lambda using Strands SDK
- **Layer 4**: Terraform with `aws_bedrockagent_agent` + action group

Three things prevent it from running on AgentCore:

1. The agent is a Lambda handler, not an HTTP server on port 8080.
2. The MCP server is spawned per invocation — fine for Lambda, broken for long-lived containers.
3. The Terraform uses the legacy `aws_bedrockagent_agent` resource, not `aws_bedrockagentcore_runtime`.

---

## Migration map

| Legacy component | AgentCore equivalent | Effort |
|------------------|---------------------|--------|
| `services/agent/index.ts` (Lambda handler) | `src/app.ts` (Express on :8080) | Rewrite (~30 lines) |
| `services/mcp-server/` (stdio subprocess) | AgentCore Gateway target (Lambda) | Move to Gateway config |
| `services/inventory-api/` (Lambda + DynamoDB) | **Unchanged** — keep as Gateway target | Zero change |
| `aws_bedrockagent_agent` + action group | `aws_bedrockagentcore_runtime` + `_gateway` | Replace in Terraform |
| `dist/agent.zip` Lambda packaging | Dockerfile + ECR push | Replace build |
| `ANTHROPIC_API_KEY` env var | Drop — use Bedrock InvokeModel via IAM | Delete |

The good news: **Layers 1 and 4's data plane (DynamoDB + the Data API Lambda) stay exactly as they are.** Only the agent layer and its packaging change.

---

## Step-by-step migration

### Step 1 — Wrap the agent in HTTP

Replace [services/agent/index.ts](../../strands-solution1/services/agent/index.ts):

```typescript
// Before (Lambda handler)
export const handler = async (event: { query: string }) => { ... };
```

with the Express version from [03-agent-code.md](03-agent-code.md):

```typescript
// After (AgentCore entrypoint)
app.post("/invocations", async (req, res) => { ... });
app.get("/ping", (_, res) => res.json({ status: "ok" }));
app.listen(8080, "0.0.0.0");
```

### Step 2 — Drop the stdio MCP subprocess

Remove this from the agent code:

```typescript
// DELETE — won't work in AgentCore
const mcpTools = await McpTool.fromServer({
  command: "node",
  args: ["/var/task/mcp-server/index.js"],
  ...
});
```

Replace with HTTP MCP via Gateway URL:

```typescript
const tools = await McpClient.connect({
  url: process.env.AGENTCORE_GATEWAY_URL!,
  transport: "streamable-http",
});
```

### Step 3 — Move MCP tools into Gateway targets

The two tools defined in `mcp-server/index.ts` (`check_stock`, `list_low_stock`) become Gateway targets pointing at the **existing** `inventory-api` Lambda. No Lambda code change needed — only Terraform additions:

```hcl
resource "aws_bedrockagentcore_gateway_target" "check_stock" {
  gateway_id = aws_bedrockagentcore_gateway.tools.id
  name       = "check_stock"
  target_configuration {
    lambda {
      lambda_arn = aws_lambda_function.api.arn   # ← existing Lambda from old project
      tool_schema {
        inline_payload = jsonencode({
          name        = "check_stock"
          description = "Check current stock levels for a product by its ID"
          inputSchema = {
            type = "object"
            properties = { productId = { type = "string" } }
            required   = ["productId"]
          }
        })
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "list_low_stock" {
  gateway_id = aws_bedrockagentcore_gateway.tools.id
  name       = "list_low_stock"
  target_configuration {
    lambda {
      lambda_arn = aws_lambda_function.api.arn
      tool_schema {
        inline_payload = jsonencode({
          name        = "list_low_stock"
          description = "List all products with stock below a given threshold"
          inputSchema = {
            type = "object"
            properties = { threshold = { type = "number", default = 10 } }
          }
        })
      }
    }
  }
}
```

> The `inventory-api` Lambda needs a small handler tweak: accept `{ productId }` or `{ threshold }` directly in the event (Gateway passes the tool input as the event body), in addition to its current API Gateway pathParameters shape. Easiest: branch on `event.pathParameters ?? event`.

### Step 4 — Containerize

Add the [Dockerfile from 03-agent-code.md](03-agent-code.md#dockerfile--arm64-node-20) at the project root and a `.dockerignore` to keep `services/inventory-api/` and `services/mcp-server/` out of the image (they're not part of the agent container anymore).

### Step 5 — Swap the Terraform

In `infra/main.tf`, **delete**:

```hcl
resource "aws_bedrockagent_agent" "strands_agent" { ... }
resource "aws_lambda_function" "agent" { ... }    # the agent Lambda
```

**Add** (full snippets in [04-terraform.md](04-terraform.md)):

```hcl
resource "aws_ecr_repository" "agent" { ... }
resource "aws_bedrockagentcore_runtime" "agent" { ... }
resource "aws_bedrockagentcore_gateway" "tools" { ... }
resource "aws_bedrockagentcore_gateway_target" "check_stock" { ... }
resource "aws_bedrockagentcore_gateway_target" "list_low_stock" { ... }
```

**Keep unchanged**:

```hcl
resource "aws_dynamodb_table" "inventory" { ... }
resource "aws_lambda_function" "api" { ... }
resource "aws_lambda_function_url" "api_url" { ... }
```

### Step 6 — Update IAM

The legacy `agent_role` policy granted `bedrock:InvokeModel` + `lambda:InvokeFunction`. Move both to the AgentCore runtime role (the agent container) and the Gateway role respectively — see [04-terraform.md § iam.tf](04-terraform.md#iamtf).

Drop the `ANTHROPIC_API_KEY` Terraform variable and the GitHub secret — Bedrock InvokeModel uses IAM.

### Step 7 — Migrate CI/CD

Replace the `terraform apply` step in the legacy [.github/workflows/deploy.yml](../../strands-solution1/.github/workflows/deploy.yml) with the docker build + push + apply flow from [05-deployment.md § CI/CD](05-deployment.md#cicd--github-actions-skeleton).

Delete:

- `Build → package ZIPs` step (no more Lambda zips for the agent)
- `ANTHROPIC_API_KEY` secret reference

Add:

- `docker buildx setup`
- `aws-actions/amazon-ecr-login@v2`
- `docker buildx build --platform linux/arm64 --push`

---

## Cutover plan (zero-downtime)

If the legacy agent is in production, run both in parallel during cutover:

1. **Week 1** — Deploy AgentCore runtime alongside legacy. Route 10% of traffic to it (your app/API decides which to call by checking a flag).
2. **Week 2** — Bump to 50%. Compare traces, error rates, token usage.
3. **Week 3** — 100% on AgentCore. Keep legacy resources deployed but unrouted.
4. **Week 4** — `terraform destroy -target=aws_bedrockagent_agent.strands_agent -target=aws_lambda_function.agent`.

The Data API Lambda and DynamoDB stay in place the entire time — both versions share them.

---

## Validation checklist

After migration, verify:

- [ ] `aws bedrock-agentcore invoke-agent-runtime` returns a result that mentions a real product ID
- [ ] CloudWatch trace shows: `/invocations` → `InvokeModel` → `Gateway:check_stock` → `Lambda:inventory-api`
- [ ] Old `aws_bedrockagent_agent` resource is no longer referenced
- [ ] No `ANTHROPIC_API_KEY` anywhere in env, secrets, or code
- [ ] Container image is `linux/arm64` (`docker inspect ${ECR_URI}:latest | grep Architecture`)
- [ ] Cost report shows AgentCore Runtime hours + Bedrock token spend (not Lambda invocations for the agent)

---

## When NOT to migrate

Stick with legacy Bedrock Agents if you:

- Only need single-turn, stateless Q&A (no session memory)
- Want AWS to fully manage the orchestration prompt and don't want to write agent code
- Have <100 invocations/day and Lambda cold-start tolerance is fine

Migrate to AgentCore when you need:

- Custom agent logic (Strands, LangGraph, hand-rolled)
- Multi-turn sessions with memory
- Lower per-invocation latency
- OAuth-protected downstream tools
- First-class traces and per-tool metrics
