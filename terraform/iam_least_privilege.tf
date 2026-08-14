############################################
# Least-privilege policy for the human/CLI user (willard-cli).
#
# Scoped to exactly the services this project touches, instead of
# AdministratorAccess. Terraform's own state-management calls (S3,
# DynamoDB) are included since they're how you interact with this
# project day-to-day.
#
# NOTE: this is intentionally broad *within* each service (e.g. ec2:*)
# rather than action-by-action — real least-privilege for a solo
# portfolio project without a security team reviewing every action is
# "scoped to the services and account you use," not "one IAM policy
# line per API call." The meaningful boundary here is: no billing
# changes, no deleting the root account's other resources, no touching
# services outside this project.
############################################

data "aws_iam_policy_document" "cli_user_scoped" {
  statement {
    sid    = "ProjectServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "rds:*",
      "route53:*",
      "route53domains:*",
      "acm:*",
      "ecr:*",
      "ssm:*",
      "cloudwatch:*",
      "sns:*",
      "logs:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMForThisProjectOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:CreateRole", "iam:DeleteRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy",
      "iam:DetachRolePolicy", "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:GetInstanceProfile", "iam:TagRole", "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project_name}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/*",
    ]
  }

  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::willbelony-cloud-project-tfstate",
      "arn:aws:s3:::willbelony-cloud-project-tfstate/*",
    ]
  }

  statement {
    sid       = "TerraformLocking"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/terraform-locks"]
  }

  statement {
    sid       = "ReadOnlyAccountInfo"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity", "ec2:DescribeRegions"]
    resources = ["*"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "cli_user_scoped" {
  name   = "${var.project_name}-cli-scoped-access"
  policy = data.aws_iam_policy_document.cli_user_scoped.json
}

# Attach the scoped policy — the old AdministratorAccess attachment gets
# removed manually via console/CLI after you've verified this works
# (see README for the exact verify-before-you-cut-the-cord steps)
resource "aws_iam_user_policy_attachment" "cli_user_scoped" {
  user       = "willard-cli"
  policy_arn = aws_iam_policy.cli_user_scoped.arn
}
