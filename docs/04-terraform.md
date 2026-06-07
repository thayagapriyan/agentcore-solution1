# 04 — Terraform IaC Reference

Complete Terraform setup for ECR + IAM + AgentCore Runtime + Gateway.

> Uses the AWS provider v5.70+ (`aws_bedrockagentcore_*` resource family; the runtime resource is `aws_bedrockagentcore_agent_runtime`). If your provider is older, upgrade with `terraform init -upgrade`.

---

## File layout

```
infra/
├── versions.tf          # provider + backend
├── variables.tf         # input variables
├── ecr.tf               # container registry
├── iam.tf               # execution role + policies
├── runtime.tf           # AgentCore Runtime
├── gateway.tf           # AgentCore Gateway + targets
├── outputs.tf
└── terraform.tfvars     # values (gitignored)
```

---

## `versions.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70.0"
    }
  }

  backend "s3" {
    bucket         = "my-tfstate-bucket"
    key            = "agentcore-solution1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "agentcore-solution1"
      ManagedBy = "terraform"
    }
  }
}
```

---

## `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "agent_name" {
  description = "Logical name for the agent — drives ECR repo and IAM role names"
  type        = string
  default     = "agentcore-solution1"
}

variable "image_tag" {
  description = "ECR image tag to deploy"
  type        = string
  default     = "latest"
}

variable "model_id" {
  description = "Bedrock model id / inference-profile passed to the runtime as MODEL_ID. Haiku 4.5 is inference-profile-only, hence the global. prefix."
  type        = string
  default     = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
}
```

---

## `ecr.tf`

```hcl
resource "aws_ecr_repository" "agent" {
  name                 = var.agent_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

---

## `iam.tf`

```hcl
# Trust policy — AgentCore Runtime assumes this role
data "aws_iam_policy_document" "agentcore_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "agent_runtime" {
  name               = "${var.agent_name}-runtime-role"
  assume_role_policy = data.aws_iam_policy_document.agentcore_trust.json
}

# Pull image from ECR
resource "aws_iam_role_policy" "ecr_pull" {
  role = aws_iam_role.agent_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ]
      Resource = "*"
    }]
  })
}

# Write logs
resource "aws_iam_role_policy" "logs" {
  role = aws_iam_role.agent_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:log-group:/aws/bedrock-agentcore/*"
    }]
  })
}

# Call Bedrock models (iter 5). Strands uses the Converse *Stream* API, so
# InvokeModelWithResponseStream is required alongside InvokeModel. The default
# model (Claude Haiku 4.5) is inference-profile-only, so the role needs the
# inference-profile ARNs plus the underlying anthropic foundation models (the
# profile fans out to those in any region) — a single foundation-model ARN is
# not enough.
resource "aws_iam_role_policy" "bedrock_invoke" {
  role = aws_iam_role.agent_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = [
        "arn:aws:bedrock:*::foundation-model/anthropic.*",
        "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
        "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:application-inference-profile/*"
      ]
    }]
  })
}

# Call Gateway (MCP tools, iter 6). The runtime invokes the Gateway's MCP
# endpoint with its IAM identity (the Gateway uses AWS_IAM inbound auth). Scoped
# to this gateway's ARN and its sub-resources.
resource "aws_iam_role_policy" "gateway_invoke" {
  role = aws_iam_role.agent_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock-agentcore:InvokeGateway"]
      Resource = [
        aws_bedrockagentcore_gateway.tools.gateway_arn,
        "${aws_bedrockagentcore_gateway.tools.gateway_arn}/*"
      ]
    }]
  })
}
```

> **X-Ray / tracing** is deliberately not in the role yet — it lands in the
> observability iteration (iter 10) as a separate appended policy, so it is not
> shown above.

---

## `runtime.tf`

The real resource is **`aws_bedrockagentcore_agent_runtime`** (the AWS provider
renamed it after these docs were first written), the container URI lives inside a
nested `agent_runtime_artifact { container_configuration { ... } }` block, and
`agent_runtime_name` must not contain hyphens. A `DEFAULT` endpoint is created
automatically, so `invoke-agent-runtime` works against `agent_runtime_arn`
without a separate endpoint resource.

```hcl
resource "aws_bedrockagentcore_agent_runtime" "agent" {
  agent_runtime_name = replace(var.agent_name, "-", "_")
  description        = "Strands agent runtime"
  role_arn           = aws_iam_role.agent_runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agent.repository_url}:${var.image_tag}"
    }
  }

  network_configuration {
    network_mode = "PUBLIC" # or "VPC" with subnet_ids + security_group_ids
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  # Keys are appended per iteration — the block is not restructured.
  environment_variables = {
    LOG_LEVEL             = "info"
    MODEL_ID              = var.model_id
    AGENTCORE_GATEWAY_URL = aws_bedrockagentcore_gateway.tools.gateway_url
  }

  depends_on = [
    aws_iam_role_policy.ecr_pull,
    aws_iam_role_policy.logs,
    aws_iam_role_policy.bedrock_invoke,
    aws_iam_role_policy.gateway_invoke,
  ]
}
```

---

## `gateway.tf` — Managed MCP endpoint (empty)

As shipped in iter 6: an **empty** Gateway (no tool targets) using **AWS_IAM**
inbound auth — the least-friction option, no Cognito/JWT to stand up. The
`authorizer_configuration` block is only required for `CUSTOM_JWT`, so it is
omitted; you set `authorizer_type = "AWS_IAM"` instead. JWT auth lands in the
production-hardening iteration.

Naming gotcha: Gateway names must match `^([0-9a-zA-Z][-]?){1,100}$` — hyphens
OK, underscores **not** (the opposite of the runtime name, which disallows
hyphens). The Gateway's own execution role exists now with **no permissions** —
iter 7 appends a `lambda:InvokeFunction` policy when the first target lands.

```hcl
# The Gateway's own execution role — it assumes this to invoke tool targets.
# Trust matches the runtime role (bedrock-agentcore service). No permissions
# attached yet; iter 7 appends a lambda:InvokeFunction policy with the target.
resource "aws_iam_role" "gateway" {
  name               = "${var.agent_name}-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.agentcore_trust.json
}

resource "aws_bedrockagentcore_gateway" "tools" {
  name            = "${var.agent_name}-gw"
  description     = "MCP tools gateway (empty, no targets)"
  role_arn        = aws_iam_role.gateway.arn
  protocol_type   = "MCP"
  authorizer_type = "AWS_IAM"
}
```

### Adding a tool target (iter 7+)

When you register the first tool, **append** a target + a Lambda-invoke policy
on the gateway role — don't edit the resources above. Example:

```hcl
resource "aws_bedrockagentcore_gateway_target" "hello_tool" {
  gateway_id = aws_bedrockagentcore_gateway.tools.id
  name       = "hello_tool"

  target_configuration {
    lambda {
      lambda_arn = aws_lambda_function.hello.arn
      tool_schema {
        inline_payload = jsonencode({
          name        = "hello_tool"
          description = "Return a canned greeting"
          inputSchema = {
            type       = "object"
            properties = {}
          }
        })
      }
    }
  }
}

# Append to the gateway role so it can invoke the target Lambda.
resource "aws_iam_role_policy" "gateway_lambda" {
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.hello.arn
    }]
  })
}
```

---

## `outputs.tf`

```hcl
output "ecr_repository_url" {
  description = "Push images here"
  value       = aws_ecr_repository.agent.repository_url
}

output "agent_runtime_role_arn" {
  description = "Execution role ARN — consumed by the runtime iteration"
  value       = aws_iam_role.agent_runtime.arn
}

output "agent_runtime_arn" {
  description = "Pass to: aws bedrock-agentcore invoke-agent-runtime --agent-runtime-arn"
  value       = aws_bedrockagentcore_agent_runtime.agent.agent_runtime_arn
}

output "agent_runtime_id" {
  description = "Runtime id (use with bedrock-agentcore-control get-agent-runtime)"
  value       = aws_bedrockagentcore_agent_runtime.agent.agent_runtime_id
}

output "gateway_url" {
  description = "MCP endpoint URL — injected into the runtime as AGENTCORE_GATEWAY_URL"
  value       = aws_bedrockagentcore_gateway.tools.gateway_url
}

output "gateway_id" {
  description = "AgentCore gateway ID"
  value       = aws_bedrockagentcore_gateway.tools.gateway_id
}
```

---

## Apply order

The resources have implicit dependencies, but on first apply Terraform may need two passes if it can't yet pull the image. Recommended sequence:

```bash
# Pass 1 — ECR + IAM only (so the registry exists for the image push)
terraform apply -target=aws_ecr_repository.agent -target=aws_iam_role.agent_runtime

# Push image (see 05-deployment.md)

# Pass 2 — everything else
terraform apply
```

---

## Cost-control knobs

| Setting | Default | Tune for cost |
|---------|---------|---------------|
| `network_mode` | `PUBLIC` | `VPC` only if needed (NAT charges) |
| ECR `image_count_more_than` | 10 | Lower for unused tags |
| CloudWatch log retention | infinite | Set to 14–30 days via `aws_cloudwatch_log_group` |
| Gateway authorizer | `AWS_IAM` | Add `CUSTOM_JWT` for prod (Cognito/IdP) |

Next: [05-deployment.md](05-deployment.md).
