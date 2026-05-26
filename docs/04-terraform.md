# 04 — Terraform IaC Reference

Complete Terraform setup for ECR + IAM + AgentCore Runtime + Gateway.

> Uses the AWS provider v5.70+ (`aws_bedrockagentcore_runtime` resource family). If your provider is older, upgrade with `terraform init -upgrade`.

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
  description = "Logical name for the AgentCore runtime"
  type        = string
  default     = "inventory-agent"
}

variable "image_tag" {
  description = "ECR image tag to deploy"
  type        = string
  default     = "latest"
}

variable "model_id" {
  description = "Bedrock foundation model"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
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

# Call Bedrock models
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
      Resource = "arn:aws:bedrock:*::foundation-model/${var.model_id}"
    }]
  })
}

# Write logs + traces
resource "aws_iam_role_policy" "observability" {
  role = aws_iam_role.agent_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/bedrock-agentcore/*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Call Gateway (MCP tools)
resource "aws_iam_role_policy" "gateway_invoke" {
  role = aws_iam_role.agent_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock-agentcore:InvokeGateway"]
      Resource = aws_bedrockagentcore_gateway.tools.arn
    }]
  })
}
```

---

## `runtime.tf`

```hcl
resource "aws_bedrockagentcore_runtime" "agent" {
  name        = var.agent_name
  description = "Strands agent for inventory queries"
  role_arn    = aws_iam_role.agent_runtime.arn

  container_configuration {
    container_uri = "${aws_ecr_repository.agent.repository_url}:${var.image_tag}"
  }

  network_configuration {
    network_mode = "PUBLIC"   # or "VPC" with subnet_ids + security_group_ids
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  environment_variables = {
    MODEL_ID              = var.model_id
    AGENTCORE_GATEWAY_URL = aws_bedrockagentcore_gateway.tools.gateway_url
    LOG_LEVEL             = "info"
  }

  depends_on = [
    aws_iam_role_policy.ecr_pull,
    aws_iam_role_policy.bedrock_invoke,
  ]
}
```

---

## `gateway.tf` — Managed MCP endpoint

```hcl
resource "aws_bedrockagentcore_gateway" "tools" {
  name        = "${var.agent_name}-gateway"
  description = "MCP tools for the inventory agent"
  role_arn    = aws_iam_role.gateway.arn

  protocol_type = "MCP"

  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url      = "https://cognito-idp.${var.aws_region}.amazonaws.com/<USER_POOL_ID>/.well-known/openid-configuration"
      allowed_audiences  = ["<CLIENT_ID>"]
    }
  }
}

# Example: register a Lambda-backed tool
resource "aws_bedrockagentcore_gateway_target" "inventory_lookup" {
  gateway_id = aws_bedrockagentcore_gateway.tools.id
  name       = "inventory_lookup"

  target_configuration {
    lambda {
      lambda_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:inventory-api"
      tool_schema {
        inline_payload = jsonencode({
          name        = "inventory_lookup"
          description = "Look up stock for a product by SKU"
          inputSchema = {
            type = "object"
            properties = {
              productId = { type = "string", description = "Product SKU" }
            }
            required = ["productId"]
          }
        })
      }
    }
  }
}

# Gateway's own role to invoke the Lambda
resource "aws_iam_role" "gateway" {
  name = "${var.agent_name}-gateway-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "gateway_lambda" {
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:inventory-api"
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

output "agent_runtime_arn" {
  description = "Use with bedrock-agentcore invoke-agent-runtime"
  value       = aws_bedrockagentcore_runtime.agent.runtime_arn
}

output "agent_runtime_endpoint" {
  description = "HTTPS endpoint (for direct HTTP clients)"
  value       = aws_bedrockagentcore_runtime.agent.runtime_endpoint
}

output "gateway_url" {
  description = "MCP endpoint registered as a tool target"
  value       = aws_bedrockagentcore_gateway.tools.gateway_url
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
| Gateway authorizer | JWT | Skip auth in dev, add for prod |

Next: [05-deployment.md](05-deployment.md).
