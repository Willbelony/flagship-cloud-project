# Flagship Cloud Project — Build Log

Phase 1: cost safety rails + networking foundation (VPC).

## Step 0 — One-time remote state backend (do this before `terraform init`)

Terraform needs somewhere to store its state file. We use S3 + DynamoDB for locking,
created manually via CLI since Terraform can't create the bucket it's about to store
its own state in.

```bash
# S3 bucket for state (bucket names are globally unique — change if taken)
aws s3api create-bucket \
  --bucket willbelony-cloud-project-tfstate \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket willbelony-cloud-project-tfstate \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket willbelony-cloud-project-tfstate \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# DynamoDB table for state locking (prevents two applies running at once)
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Both are free at this scale (a few KB of state, on-demand DynamoDB with near-zero requests).

## Step 1 — Init and apply the networking layer

```bash
cd terraform
terraform init
terraform plan     # review what it's about to create — should be: 1 VPC, 1 IGW,
                    # 4 subnets, 2 route tables, 4 route table associations
terraform apply     # type "yes" when prompted
```

This creates:
- 1 VPC (`10.0.0.0/16`)
- 2 public subnets (one per AZ) — where your EC2 instance and later load balancer live
- 2 private subnets (one per AZ) — where RDS will live in a later phase
- 1 Internet Gateway + public route table
- **No NAT Gateway** — deliberately, since it's the one networking piece with a real
  monthly cost (~$32) and this project doesn't need private subnets to reach the internet

## Verify

```bash
terraform output
```

You should see `vpc_id`, `public_subnet_ids` (2), and `private_subnet_ids` (2).

## What this proves (for interviews)

- You understand the difference between public and private subnets and *why* each route
  table is different, not just that Terraform made them
- You made a deliberate cost/architecture tradeoff (no NAT) instead of copy-pasting a
  tutorial's default setup
- Remote state + locking shows you know Terraform in a team/real-world context, not just
  `terraform apply` on a laptop with local state

## Next phases (not yet built)

1. **Security groups + EC2 + Docker** — the app itself, SSH-free access via SSM Session Manager
2. **RDS Postgres** — in the private subnets, security-group-scoped to the app only
3. **ALB + Route 53 + ACM** — real HTTPS on a real domain
4. **GitHub Actions CI/CD** — build → push → deploy on merge
5. **CloudWatch monitoring + alarms**
6. **IAM least-privilege tightening** — replace your admin user's broad access with
   scoped roles once everything else works

## Tearing everything down (avoid charges)

```bash
cd terraform
terraform destroy
```

Run this anytime you're stepping away from the project for more than a day or two.
