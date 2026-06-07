# Iter 9: durable session storage. The agent persists Strands conversation
# snapshots to this bucket via a custom S3 SnapshotStorage (keyed by sessionId),
# wired through the SDK's SessionManager. Sessions are optional — the agent only
# uses the bucket when SESSION_BUCKET is set (see runtime.tf); unset = stateless.

resource "aws_s3_bucket" "sessions" {
  bucket = "${var.agent_name}-sessions-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "sessions" {
  bucket                  = aws_s3_bucket.sessions.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sessions" {
  bucket = aws_s3_bucket.sessions.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Snapshots are conversation state, not a system of record — expire them so the
# bucket doesn't grow unbounded. snapshot_latest.json is rewritten each turn, so
# 30 days of inactivity is a safe TTL for abandoned sessions.
resource "aws_s3_bucket_lifecycle_configuration" "sessions" {
  bucket = aws_s3_bucket.sessions.id
  rule {
    id     = "expire-stale-sessions"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

# Append to the runtime role: read/write/list/delete session snapshots. New
# policy resource — existing runtime-role policies are untouched (additive).
resource "aws_iam_role_policy" "session_rw" {
  role = aws_iam_role.agent_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.sessions.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.sessions.arn
      }
    ]
  })
}
