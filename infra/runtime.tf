# AgentCore Runtime — wired to the ECR image from iter 3.
# Iter 4 scope: prove the plumbing (ECR -> runtime -> invocation -> response)
# returning the hardcoded "hello". No model call, no Gateway yet.
#
# Real resource name is aws_bedrockagentcore_agent_runtime (the docs predate the
# provider rename). A DEFAULT endpoint is created automatically, so
# invoke-agent-runtime works against agent_runtime_arn without a separate
# endpoint resource.

resource "aws_bedrockagentcore_agent_runtime" "agent" {
  agent_runtime_name = replace(var.agent_name, "-", "_")
  description        = "Strands agent runtime (iter 4: hello stub)"
  role_arn           = aws_iam_role.agent_runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agent.repository_url}:${var.image_tag}"
    }
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  # Keys are appended per iteration — the block is not restructured.
  environment_variables = {
    LOG_LEVEL             = "info"
    MODEL_ID              = var.model_id
    AGENTCORE_GATEWAY_URL = aws_bedrockagentcore_gateway.tools.gateway_url
    # Iter 7: the agent caches the gateway tool list per container lifetime
    # (boot-time listTools()). Adding/changing a gateway target does NOT restart
    # the container, so a fresh container is needed to pick up new tools. Bump
    # this marker whenever the tool set changes to force a new runtime version
    # (and thus a fresh container) without rebuilding the image.
    TOOLS_REV = "iter7-hello-tool"
  }

  depends_on = [
    aws_iam_role_policy.ecr_pull,
    aws_iam_role_policy.logs,
    aws_iam_role_policy.bedrock_invoke,
    aws_iam_role_policy.gateway_invoke,
  ]
}
