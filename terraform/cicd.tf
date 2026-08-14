############################################
# ECR — private Docker registry for the app image
############################################

resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}/task-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

# Keep only the last 10 images so storage never grows unbounded
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

############################################
# GitHub OIDC — lets GitHub Actions assume an AWS role per-run using a
# short-lived token, with no long-lived AWS access keys stored as a
# GitHub secret. AWS trusts GitHub's identity provider directly.
############################################

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy role, as owner/repo"
  type        = string
  default     = "Willbelony/flagship-cloud-project"
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to this exact repo, any branch — tighten to :ref:refs/heads/main
    # if you want to block deploys from feature branches later
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "${var.project_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "SSMDeploy"
    actions   = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:*:instance/${aws_instance.app.id}",
      "arn:aws:ssm:${var.aws_region}:*:document/AWS-RunShellScript",
    ]
  }

  statement {
    sid       = "SSMCheckResult"
    actions   = ["ssm:GetCommandInvocation"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "${var.project_name}-github-deploy"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}

############################################
# Let the EC2 instance pull from ECR (it already has SSM + the DB param
# read permission from earlier phases; this adds registry pull access)
############################################

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "${var.project_name}-ecr-pull"
  role   = aws_iam_role.app_instance.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}
