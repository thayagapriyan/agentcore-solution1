# Iter 7: the simplest possible tool — a Lambda that returns canned data. The
# gateway exposes it as an MCP tool target (see gateway_target.tf). Kept inline
# (no build step, no separate source dir) because the whole point is a trivial
# first tool; real tools get their own packaging in iter 8.

data "archive_file" "hello_tool" {
  type        = "zip"
  output_path = "${path.module}/.build/hello_tool.zip"

  source {
    # Gateway invokes the Lambda with the tool's input as the event and expects
    # the tool result as the return value. Canned greeting, ignores input.
    content  = <<-JS
      export const handler = async () => ({ greeting: "hi from lambda" });
    JS
    filename = "index.mjs"
  }
}

# Lambda's own execution role — basic Lambda logging only. This is NOT the
# gateway role; the gateway assumes its own role (gateway.tf) to invoke this
# function (see the lambda:InvokeFunction policy in gateway_target.tf).
resource "aws_iam_role" "hello_tool" {
  name = "${var.agent_name}-hello-tool-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "hello_tool_logs" {
  role       = aws_iam_role.hello_tool.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hello_tool" {
  function_name    = "${var.agent_name}-hello-tool"
  role             = aws_iam_role.hello_tool.arn
  runtime          = "nodejs20.x"
  architectures    = ["arm64"]
  handler          = "index.handler"
  filename         = data.archive_file.hello_tool.output_path
  source_code_hash = data.archive_file.hello_tool.output_base64sha256
  timeout          = 10
}

# ---------------------------------------------------------------------------
# Iter 8a: an "add" tool that takes real input (a, b) and returns their sum.
# Same standardized pattern as hello_tool (own log-only role, inline source),
# but exercises the input_schema property path the zero-arg hello_tool did not.
# ---------------------------------------------------------------------------

data "archive_file" "add_tool" {
  type        = "zip"
  output_path = "${path.module}/.build/add_tool.zip"

  source {
    # The gateway passes the tool's arguments as the event. Coerce to numbers
    # so string inputs ("17") still sum correctly; return the result object.
    content  = <<-JS
      export const handler = async (event) => {
        const a = Number(event?.a);
        const b = Number(event?.b);
        if (Number.isNaN(a) || Number.isNaN(b)) {
          return { error: "both 'a' and 'b' must be numbers" };
        }
        return { sum: a + b };
      };
    JS
    filename = "index.mjs"
  }
}

resource "aws_iam_role" "add_tool" {
  name = "${var.agent_name}-add-tool-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "add_tool_logs" {
  role       = aws_iam_role.add_tool.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "add_tool" {
  function_name    = "${var.agent_name}-add-tool"
  role             = aws_iam_role.add_tool.arn
  runtime          = "nodejs20.x"
  architectures    = ["arm64"]
  handler          = "index.handler"
  filename         = data.archive_file.add_tool.output_path
  source_code_hash = data.archive_file.add_tool.output_base64sha256
  timeout          = 10
}
