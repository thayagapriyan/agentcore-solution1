output "ecr_repository_url" {
  description = "Push images here"
  value       = aws_ecr_repository.agent.repository_url
}

output "agent_runtime_role_arn" {
  description = "Execution role ARN — consumed by the runtime iteration"
  value       = aws_iam_role.agent_runtime.arn
}
