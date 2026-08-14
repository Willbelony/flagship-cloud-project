# Interview Prep — Flagship Cloud Project

Go through this out loud, not just in your head. If you can't explain an answer without looking at
it, that's the one to redo tomorrow.

---

## Networking (VPC)

**Q: Walk me through your network architecture.**
A: One VPC, `10.0.0.0/16`. Two public subnets and two private subnets, split across two
Availability Zones for redundancy. Public subnets hold the EC2 instance and the load balancer —
they have a route to an Internet Gateway. Private subnets hold only RDS — no internet route at
all, since the database never needs to reach out.

**Q: Why no NAT Gateway?**
A: A NAT Gateway costs about $32/month and exists specifically so private-subnet resources can
reach the internet. My database doesn't need outbound internet access, so paying for a NAT
Gateway would've been cost with no corresponding benefit. If I later added something in a private
subnet that *did* need outbound access (e.g., a worker pulling from an external API), I'd add one
then.

**Q: What's the actual difference between a public and private subnet in AWS?**
A: There's no inherent "public" or "private" flag on a subnet — it's entirely about the route
table. A subnet is "public" if its route table sends `0.0.0.0/0` traffic to an Internet Gateway.
Mine does that for the public subnets and doesn't for the private ones.

---

## Compute (EC2 + Docker)

**Q: Why EC2 instead of ECS Fargate or Lambda?**
A: Two reasons. First, cost — Fargate has an always-on minimum cost, while EC2 t3.micro is Free
Tier eligible for 750 hours/month. Second, and more important for me: I wanted hands-on reps with
actual Linux administration — systemd, the Docker daemon, package management — rather than
abstracting the OS away entirely. Given my coursework is Linux-heavy, this let the project
reinforce that instead of skipping past it.

**Q: How do you access the instance for maintenance?**
A: AWS Systems Manager Session Manager, not SSH. No port 22 is open anywhere in my security
groups. SSM uses my IAM role to authorize a session, and every command run through it is logged in
CloudTrail. If someone stole my laptop, they couldn't SSH in — they'd need valid AWS credentials
AND the right IAM permissions, which is a meaningfully higher bar than "has the SSH key."

**Q: What's actually running on the box?**
A: A single Docker container running the FastAPI app via Uvicorn, built from a Dockerfile that
installs dependencies, copies the app code, creates a non-root user to run as, and exposes port
8000.

---

## Database (RDS)

**Q: Why RDS instead of running Postgres yourself on the EC2 box?**
A: Managed backups, automated patching, and it's genuinely more realistic of how companies do
this — you rarely see hand-rolled databases on app servers in production. I did weigh
self-hosting Postgres on EC2 for extra Linux reps, but decided the RDS operational model (backup
retention, subnet groups, parameter groups) was worth learning too.

**Q: How does the app get the database password?**
A: It's never in code, never in the Docker image, never in an environment file committed to git.
Terraform generates it randomly and stores it in SSM Parameter Store as a SecureString (encrypted
with KMS). The EC2 instance's IAM role has permission to read that one specific parameter — nothing
else in Parameter Store. At deploy time, a script fetches it and passes it as an environment
variable to the container at runtime.

**Q: Can the database be reached from the internet?**
A: No — `publicly_accessible = false`, it's in the private subnets with no internet route, and its
security group only allows inbound traffic on port 5432 from the *application's* security group
specifically, not from any IP address or CIDR range.

---

## Load Balancer & HTTPS

**Q: Why put a load balancer in front of a single instance?**
A: Right now, yes, it's fronting one instance — but the point wasn't just today's traffic. The ALB
is what let me get a stable public entry point (my home IP kept changing, which is its own story),
terminate TLS in one place instead of on the app server, and it sets up cleanly for adding a second
instance and auto-scaling later without changing the app or DNS at all.

**Q: How does HTTPS actually work here?**
A: ACM issued a certificate for my domain, validated via a DNS record Terraform created
automatically in Route 53. The ALB terminates TLS — meaning the encrypted connection ends at the
load balancer, and traffic from the ALB to the EC2 instance is plain HTTP inside the AWS network.
Port 80 on the ALB redirects to port 443 with a 301, so nothing is ever served unencrypted to a
client.

**Q: Tell me about a real bug you hit.**
A: Testing directly against the EC2 instance's IP with a security group allowlisting my home IP,
`curl` kept timing out. I checked `curl ifconfig.me` and got an IPv6 address one time and a
different IPv4 address the next — my home network doesn't have a stable public IPv4 address
(common with CGNAT). IP-based access control was fundamentally the wrong model for my situation.
Rather than keep patching it, I moved to the ALB, which doesn't care what IP the client is coming
from at all.

---

## CI/CD

**Q: Walk me through what happens when you push code.**
A: GitHub Actions triggers on a push to `main` that touches the `app/` folder. It requests a
short-lived OIDC token from GitHub's identity provider, uses that to assume an AWS IAM role (no
stored AWS keys anywhere in GitHub), logs into ECR, builds the Docker image, pushes it tagged with
the commit SHA and `latest`, then uses SSM Run Command to tell the EC2 instance to pull the new
image and restart the container. A final step curls the health endpoint to confirm the deploy
actually worked.

**Q: Why OIDC instead of just storing AWS access keys as a GitHub secret?**
A: Stored keys are long-lived — if they leak, they're valid until someone manually rotates them.
OIDC tokens are minted fresh for each workflow run and expire almost immediately. AWS trusts
GitHub's identity provider directly and only allows the role to be assumed by tokens whose claims
match my specific repo. There's no persistent secret sitting in GitHub for someone to steal.

**Q: Tell me about the hardest bug you hit on this whole project.**
A: The OIDC role assumption started failing with "not authorized" right after I set it up —
looked like a permissions problem. I checked the trust policy in IAM and it looked correct. Instead
of guessing further, I went to CloudTrail and looked at the actual `AssumeRoleWithWebIdentity`
events, which show exactly what claims GitHub sent versus what AWS evaluated. Turned out GitHub had
rolled out a change days earlier: new repos get an "immutable subject claim" format that embeds
numeric owner and repo IDs, specifically to prevent a renamed or recycled repo from inheriting
someone else's trust policy. My trust policy was written for the old plain-text format. I updated
it to match the new format and it worked immediately. The lesson I'd give: when something that
"should" work doesn't, check what's actually being sent over the wire before assuming your own
config is wrong.

---

## Monitoring

**Q: How would you know if this went down?**
A: CloudWatch alarms on five things: EC2 CPU, RDS CPU, RDS free storage, ALB 5xx error count, and
ALB unhealthy target count. All of them publish to an SNS topic that emails me. I also have a
CloudWatch dashboard showing request volume, response codes, response time, and resource
utilization on one screen.

**Q: What would you add if this were a real production system with a team?**
A: Structured application logging shipped to CloudWatch Logs (right now I only have infrastructure
metrics, not application-level logs beyond container stdout). PagerDuty or similar instead of raw
email for actual on-call escalation. And probably X-Ray or a similar tracing tool once there's more
than one service to trace requests across.

---

## Security / IAM

**Q: How did you handle permissions?**
A: Two different IAM identities with two different scopes. The EC2 instance has a role that can
only do what it needs: use SSM, read one specific SSM parameter, pull from one specific ECR repo.
The GitHub Actions deploy role can push to that ECR repo and send SSM commands to that one
instance — nothing else. My own CLI user started with full admin access to move fast while
building, then I replaced that with a policy scoped to just the services this project touches, once
everything worked.

**Q: Why not just use admin access the whole time — isn't that easier?**
A: It's faster during initial build, which is why I used it then. But leaving it in place long-term
means one leaked credential has access to the entire AWS account, not just this project. Scoping it
down afterward is a deliberate, standard step — verify the narrower policy works before removing
the broad one, so you don't lock yourself out.

---

## Cost

**Q: What does this cost to run?**
A: Within AWS Free Tier for the first 12 months — EC2 t3.micro and RDS db.t3.micro both get 750
free hours/month, RDS gets 20GB free storage. The only real recurring cost is domain registration,
about $16/year. After Free Tier expires, realistically $15-25/month for the EC2 and RDS instance
hours.

**Q: How did you avoid a surprise bill while building this?**
A: Set a zero-spend billing alarm before creating any AWS resources — emails me the instant any
charge occurs, even $0.01. I also deliberately avoided the one networking piece with a real
ongoing cost (NAT Gateway) and stuck to Free Tier-eligible instance sizes throughout, with
Terraform comments flagging exactly why each size was chosen.

---

## If they ask "what would you do differently"

Have 2-3 honest answers ready, not zero. Good options:
- Self-host Postgres on EC2 instead of RDS for more hands-on database administration reps, or run
  both to compare operational overhead
- Add a staging environment / separate Terraform workspace so deploys can be tested before hitting
  the domain that's live
- Application-level structured logging, not just infra metrics
- Multi-AZ EC2 with an Auto Scaling Group instead of a single instance, now that the ALB is already
  in place to support it
