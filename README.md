# Flagship Cloud Project

A production-shaped deployment of a small FastAPI task-tracker service — built to demonstrate real
AWS infrastructure, not a tutorial checklist. Live at **https://willardbelony.com**

## Architecture

```
Internet
   │
   ▼
Route 53 (willardbelony.com)
   │
   ▼
Application Load Balancer  ──── ACM (TLS cert, HTTP→HTTPS redirect)
   │  (public subnets)
   ▼
EC2 (t3.micro, Docker)  ──────── CloudWatch alarms + dashboard
   │  (public subnet, SG: ALB-only)         │
   ▼                                         ▼
RDS Postgres (private subnets, SG: app-only)  SNS → email
```

**CI/CD:** GitHub Actions → OIDC-federated AWS role (no stored credentials) → builds/pushes
Docker image to ECR → SSM Run Command redeploys on EC2 → health check confirms.

## Why these choices

- **EC2 over Fargate/Lambda** — deliberately chosen for hands-on Linux administration reps
  (systemd, Docker daemon, SSM agent) rather than abstracting the OS away.
- **No NAT Gateway** — the one AWS networking component with a real ongoing cost (~$32/mo).
  Private subnets only host RDS, which doesn't need outbound internet.
- **SSM Session Manager instead of SSH** — zero open inbound ports for shell access, IAM-governed,
  fully audited in CloudTrail.
- **Security groups over IP allowlisting** — app trusts only the ALB's security group, DB trusts
  only the app's. No IP address anywhere in the trust chain (this was a real bug I hit and fixed —
  see below).
- **GitHub OIDC over stored AWS keys** — GitHub proves its identity per-run via a short-lived
  token; no long-lived credential sits in a GitHub secret waiting to leak.

## Real problems hit and fixed (not just "it worked first try")

1. **RDS AMI snapshot size mismatch** — Amazon Linux 2023's AMI requires a ≥30GB root volume;
   Terraform's default 8GB failed with a clear API error. Fixed by matching the snapshot minimum.
2. **CGNAT/IPv6 broke IP-based security group rules** — my home network doesn't have a stable
   public IPv4 address, so allowlisting my IP for testing was fragile. Root-caused via `curl -4`
   vs default `curl`, then eliminated the pattern entirely by moving to an ALB.
3. **GitHub's July 2026 OIDC "immutable subject claim" rollout** broke the trust policy mid-project
   — GitHub started embedding numeric owner/repo IDs in the token's `sub` claim for new repos.
   Diagnosed via raw CloudTrail `AssumeRoleWithWebIdentity` event logs (not guessing), found the
   exact claim format, updated the Terraform trust policy to match.

## Tech stack

Terraform · AWS (VPC, EC2, RDS, ALB, Route 53, ACM, IAM/OIDC, ECR, SSM, CloudWatch, SNS) · Docker ·
FastAPI · SQLAlchemy · Postgres · GitHub Actions

## Repo layout

```
app/            FastAPI app, Dockerfile
terraform/      All infrastructure as code
.github/workflows/deploy.yml   CI/CD pipeline
```

## Running this yourself

```bash
cd terraform
terraform init
terraform apply -var="domain_name=<your-domain>"
```

Requires: AWS account, registered domain in Route 53, `terraform`, `aws` CLI configured.

## Cost

Runs within AWS Free Tier (EC2 t3.micro, RDS db.t3.micro, 20GB storage) for the first 12 months.
Ongoing cost after Free Tier: roughly $15-25/month (EC2 + RDS instance hours) + ~$16/year domain
registration. Zero-spend billing alarm configured from day one.

## Teardown

```bash
cd terraform
terraform destroy -var="domain_name=<your-domain>"
```
