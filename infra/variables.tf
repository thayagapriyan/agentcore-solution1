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
  description = "ECR image tag to deploy (unused until the runtime iteration)"
  type        = string
  default     = "latest"
}
