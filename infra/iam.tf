data "aws_caller_identity" "current" {}

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

resource "aws_iam_role" "agent_runtime" {
  name               = "${var.agent_name}-runtime-role"
  assume_role_policy = data.aws_iam_policy_document.agentcore_trust.json
}

# Minimal perms for this iteration: pull image from ECR + write logs.
# Later iterations APPEND new aws_iam_role_policy resources (Bedrock, Gateway,
# X-Ray) — never edit this role's existing policies in place.

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

# Iter 5: invoke the Bedrock model. Strands uses the Converse *Stream* API, so
# InvokeModelWithResponseStream is required alongside InvokeModel. The default
# model (Claude Haiku 4.5) is inference-profile-only, so the role needs the
# inference-profile ARNs plus the underlying anthropic foundation models (the
# profile fans out to those in any region).
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

# Iter 6: the runtime invokes the Gateway's MCP endpoint with its IAM identity
# (the Gateway uses AWS_IAM inbound auth). Scoped to this gateway's ARN.
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
