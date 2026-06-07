# Iter 7: register the hello-tool Lambda as an MCP tool on the existing (iter-6)
# gateway. Additive — gateway.tf and its role are untouched; this file adds the
# target plus the one policy that lets the gateway role invoke the Lambda.
#
# Provider v6 shape: the Lambda target lives at
#   target_configuration { mcp { lambda { tool_schema { inline_payload { ... }}}}}
# as structured HCL (not a jsonencode'd string), and the gateway authenticates
# to the target with its own IAM role via credential_provider_configuration {
# gateway_iam_role {} }.

# Target name follows the gateway naming rule (^([0-9a-zA-Z][-]?){1,100}$):
# hyphens OK, underscores NOT — hence "hello-tool". The MCP tool the agent
# actually calls is inline_payload.name below ("hello_tool"), which has no such
# restriction.
resource "aws_bedrockagentcore_gateway_target" "hello_tool" {
  gateway_identifier = aws_bedrockagentcore_gateway.tools.gateway_id
  name               = "hello-tool"
  description        = "Returns a canned greeting (iter-7 first tool)"

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.hello_tool.arn

        tool_schema {
          inline_payload {
            name        = "hello_tool"
            description = "Return a friendly canned greeting. Use it when the user asks to be greeted."

            # Zero-argument tool: an object schema with no properties.
            input_schema {
              type = "object"
            }
          }
        }
      }
    }
  }

  # The gateway calls the Lambda using its own execution role (gateway.tf).
  credential_provider_configuration {
    gateway_iam_role {}
  }
}

# Append to the gateway role so it can invoke the hello-tool Lambda. New policy
# resource — the gateway role's existing config (empty in iter 6) is not edited.
resource "aws_iam_role_policy" "gateway_lambda" {
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.hello_tool.arn
    }]
  })
}

# ---------------------------------------------------------------------------
# Iter 8a: register the add-tool. Same shape as hello-tool, but the
# inline_payload carries a real input_schema with two required number
# properties (a, b) — the first input-taking tool. Additive: hello-tool and its
# policy are untouched.
# ---------------------------------------------------------------------------
resource "aws_bedrockagentcore_gateway_target" "add_tool" {
  gateway_identifier = aws_bedrockagentcore_gateway.tools.gateway_id
  name               = "add-tool"
  description        = "Adds two numbers (iter-8a, first input-taking tool)"

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.add_tool.arn

        tool_schema {
          inline_payload {
            name        = "add"
            description = "Add two numbers and return their sum. Use it for arithmetic addition."

            input_schema {
              type = "object"

              property {
                name        = "a"
                type        = "number"
                description = "The first addend"
                required    = true
              }
              property {
                name        = "b"
                type        = "number"
                description = "The second addend"
                required    = true
              }
            }
          }
        }
      }
    }
  }

  credential_provider_configuration {
    gateway_iam_role {}
  }
}

# Gateway role also needs to invoke the add-tool Lambda. New policy resource —
# the iter-7 gateway_lambda policy is left untouched (additive per-tool).
resource "aws_iam_role_policy" "gateway_lambda_add" {
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.add_tool.arn
    }]
  })
}
