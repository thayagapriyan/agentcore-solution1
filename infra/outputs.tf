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
