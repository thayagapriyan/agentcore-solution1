# Iter 11: CI/CD via GitHub Actions + OIDC. Additive — no existing resource is
# changed. The provider + role here are the trust anchor the deploy workflow
# assumes; after the one-time bootstrap workflow creates them, every later change
# to this file deploys through the pipeline like any other infra.
#
# Bootstrap chicken-and-egg: the role can't create itself from inside the
# workflow on the very first run, so .github/workflows/bootstrap.yml applies just
# these two resources once (using a temporary Actions secret), then writes the
# role ARN into Actions vars. See that workflow for the exact sequence.

# GitHub's OIDC issuer. The thumbprint is no longer validated by AWS for the
# github token issuer, but the provider requires the argument; this is GitHub's
# well-known intermediate CA thumbprint.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Scope to this repo only — any branch/PR/tag. Tighten to a specific
    # environment (e.g. ":environment:production") when staging lands in iter 12.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.agent_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

# The deploy job runs the full `terraform apply`, so the role needs to manage
# every resource in this stack: ECR (push + manage), Bedrock AgentCore runtime &
# gateway, Lambda, S3 (sessions bucket + tfstate backend), CloudWatch logs, and
# IAM (it manages the runtime role, gateway role, and this very role). PowerUser
# covers the non-IAM services; IAM is granted separately and scoped to the
# project's own role/policy names rather than account-wide.
resource "aws_iam_role_policy_attachment" "github_deploy_poweruser" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "github_deploy_iam" {
  # Manage the roles/policies this stack owns. Scoped by name prefix so the
  # deploy role can't touch unrelated IAM in the account.
  statement {
    sid    = "ManageProjectRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.agent_name}-*",
    ]
  }

  # The OIDC provider is a global IAM resource (no name prefix possible). Limited
  # to the GitHub issuer so the role can reconcile its own trust anchor.
  statement {
    sid    = "ManageGithubOidcProvider"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }
}

resource "aws_iam_role_policy" "github_deploy_iam" {
  name   = "manage-project-iam"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_iam.json
}

# Terraform's S3 backend: the deploy job runs `terraform init`, so the role must
# read/write the state object and its lock file. Bucket name mirrors versions.tf.
data "aws_iam_policy_document" "github_deploy_tfstate" {
  statement {
    sid       = "TfStateObject"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::warewise-tfstate-224193574799/agentcore-solution1/*"]
  }
  statement {
    sid       = "TfStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::warewise-tfstate-224193574799"]
  }
}

resource "aws_iam_role_policy" "github_deploy_tfstate" {
  name   = "tfstate-backend-access"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_tfstate.json
}
