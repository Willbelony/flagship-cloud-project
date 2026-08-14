# Flagship Cloud Project

A small task-tracker app deployed on real AWS infrastructure — Terraform, EC2, RDS, an
Application Load Balancer, CI/CD, monitoring, the works. Live at **https://willardbelony.com**

The app is intentionally simple. The point of this project is the infrastructure around it.

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

CI/CD: push to `main` → GitHub Actions authenticates to AWS via OIDC (no stored keys) → builds and
pushes a Docker image to ECR → SSM Run Command redeploys it on the EC2 instance → health check
confirms it worked.

## A few decisions worth explaining

- **EC2 instead of Fargate or Lambda.** Wanted actual Linux administration reps — systemd, the
  Docker daemon, SSM — instead of the OS being abstracted away.
- **No NAT Gateway.** It's the one piece of AWS networking with a real recurring cost (~$32/mo).
  My private subnets only hold RDS, and RDS doesn't need outbound internet, so there was nothing
  to gain by adding one.
- **SSM Session Manager instead of SSH.** No port 22 open anywhere. Access goes through IAM and
  gets logged in CloudTrail.
- **Security groups instead of IP allowlisting.** The app only trusts the load balancer's security
  group, the database only trusts the app's. No IP addresses anywhere in the chain — I tried IP
  allowlisting first and it broke on me (see below).
- **GitHub OIDC instead of stored AWS keys.** GitHub authenticates per workflow run with a
  short-lived token instead of a long-lived secret sitting in the repo settings.

## Bugs I actually hit

**RDS wouldn't launch with an 8GB root volume.** Amazon Linux 2023's AMI needs at least 30GB —
Terraform's error message said so directly, just bumped the volume size to match.

**My home IP kept changing mid-testing.** Turns out my ISP doesn't give me a stable IPv4 address —
`curl ifconfig.me` returned IPv6 one time, a different IPv4 the next. Allowlisting my IP for the
security group was never going to work reliably, so I moved everything behind the ALB instead and
dropped IP-based rules entirely.

**GitHub broke my CI/CD pipeline a few days after I built it.** The OIDC role assumption started
failing with an auth error out of nowhere. I checked the trust policy — looked fine. Pulled the
actual `AssumeRoleWithWebIdentity` events from CloudTrail and found GitHub had rolled out a new
token format that embeds numeric owner/repo IDs (to stop renamed repos from inheriting old trust).
Updated the Terraform trust policy to match the new format and it worked.

## Stack

Terraform, AWS (VPC, EC2, RDS, ALB, Route 53, ACM, IAM/OIDC, ECR, SSM, CloudWatch, SNS), Docker,
FastAPI, SQLAlchemy, Postgres, GitHub Actions.

## Layout

```
app/            FastAPI app, Dockerfile
terraform/      infrastructure as code
.github/workflows/deploy.yml
```

## Running it yourself

```bash
cd terraform
terraform init
terraform apply -var="domain_name=<your-domain>"
```

Needs an AWS account, a domain registered in Route 53, and the `terraform`/`aws` CLIs configured.

## Cost

Free Tier covers EC2 t3.micro and RDS db.t3.micro for the first year. After that, roughly
$15-25/month for the two instances, plus ~$16/year for the domain. Zero-spend billing alarm was
the first thing I set up, before creating any resources.

## Tearing it down

```bash
cd terraform
terraform destroy -var="domain_name=<your-domain>"
```
