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
  description = "AgentCore runtime ID"
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

output "hello_tool_lambda_arn" {
  description = "Iter 7: ARN of the hello-tool Lambda backing the gateway target"
  value       = aws_lambda_function.hello_tool.arn
}

output "hello_tool_target_id" {
  description = "Iter 7: gateway target id for the hello_tool MCP tool"
  value       = aws_bedrockagentcore_gateway_target.hello_tool.target_id
}

output "add_tool_lambda_arn" {
  description = "Iter 8a: ARN of the add-tool Lambda backing the gateway target"
  value       = aws_lambda_function.add_tool.arn
}

output "add_tool_target_id" {
  description = "Iter 8a: gateway target id for the add MCP tool"
  value       = aws_bedrockagentcore_gateway_target.add_tool.target_id
}

output "session_bucket" {
  description = "Iter 9: S3 bucket holding conversation snapshots (SESSION_BUCKET)"
  value       = aws_s3_bucket.sessions.id
}
