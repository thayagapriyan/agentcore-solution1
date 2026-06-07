# Iter 6: empty AgentCore Gateway (MCP protocol, AWS_IAM inbound auth). No tool
# targets yet — iter 7 appends aws_bedrockagentcore_gateway_target. The agent
# connects to gateway_url only when AGENTCORE_GATEWAY_URL is set, so behavior is
# unchanged at 0 tools.
#
# AWS_IAM is the least-friction inbound auth (no Cognito/JWT to stand up). The
# authorizer_configuration block is only required for CUSTOM_JWT, so it is
# omitted here.

# The Gateway's own execution role — it assumes this to invoke tool targets.
# Trust matches the runtime role (bedrock-agentcore service). No permissions
# attached yet; iter 7 appends a lambda:InvokeFunction policy when a target is
# registered.
resource "aws_iam_role" "gateway" {
  name               = "${var.agent_name}-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.agentcore_trust.json
}

# Gateway names must match ^([0-9a-zA-Z][-]?){1,100}$ — hyphens OK, underscores
# NOT (the opposite of the runtime name, which disallows hyphens).
resource "aws_bedrockagentcore_gateway" "tools" {
  name          = "${var.agent_name}-gw"
  description   = "MCP tools gateway"
  role_arn      = aws_iam_role.gateway.arn
  protocol_type = "MCP"
  # Iter 7: NONE (no inbound auth). The Strands McpClient transport makes
  # unsigned HTTPS calls — it supports OAuth/JWT and static headers but cannot
  # SigV4-sign, so the iter-6 AWS_IAM choice left the agent unable to authenticate
  # to the gateway (0 tools loaded). NONE lets the agent reach the MCP endpoint;
  # JWT auth is revisited in the production-hardening iteration.
  authorizer_type = "NONE"
}
