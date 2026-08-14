# Interview Prep — Flagship Cloud Project

Read these out loud, not just in your head. If you can't answer one without looking, that's the
one to go over again tomorrow.

---

## Networking (VPC)

**Q: Walk me through your network setup.**
A: One VPC, `10.0.0.0/16`, split into two public and two private subnets across two Availability
Zones. Public subnets hold the EC2 instance and the load balancer and route out through an
Internet Gateway. Private subnets only hold RDS and have no route to the internet at all.

**Q: Why no NAT Gateway?**
A: It costs about $32/month and its whole job is letting private-subnet resources reach the
internet. My database doesn't need that, so it would've been pure cost with nothing to show for
it.

**Q: What actually makes a subnet "public" vs "private" in AWS?**
A: It's not a setting on the subnet itself — it's the route table. A subnet is public if its route
table sends `0.0.0.0/0` to an Internet Gateway. Mine does for the two public subnets and doesn't
for the private ones.

---

## Compute (EC2 + Docker)

**Q: Why EC2 instead of Fargate or Lambda?**
A: Cost was part of it — EC2 t3.micro is Free Tier eligible, Fargate isn't. But mostly I wanted
hands-on Linux practice, since my coursework leans that direction — systemd, the Docker daemon,
package management. Fargate abstracts all of that away.

**Q: How do you access the instance?**
A: SSM Session Manager, not SSH. No port 22 open in any security group. SSM authorizes through my
IAM role and every session is logged in CloudTrail.

**Q: What's running on it?**
A: One Docker container, running the FastAPI app through Uvicorn. The Dockerfile installs
dependencies, copies the app in, creates a non-root user to run it as, exposes port 8000.

---

## Database (RDS)

**Q: Why RDS instead of just running Postgres on the EC2 box yourself?**
A: Managed backups and patching, and it's closer to how this is usually done in practice. I
thought about self-hosting it for more Linux reps but decided learning the RDS side (subnet
groups, parameter groups, backup retention) was worth it too.

**Q: Where does the app get the database password?**
A: Never in code, never in the image, never committed anywhere. Terraform generates it randomly
and stores it in SSM Parameter Store as an encrypted SecureString. The EC2 role can read that one
parameter and nothing else in the store. A deploy script fetches it and passes it in as an
environment variable at runtime.

**Q: Can the database be reached from the internet?**
A: No. It's not publicly accessible, it sits in private subnets with no internet route, and its
security group only allows Postgres traffic from the app's security group — not an IP, not a CIDR
block.

---

## Load Balancer & HTTPS

**Q: Why a load balancer for one instance?**
A: Partly for a stable public entry point — my home IP kept changing, which caused real problems
early on. Partly because it terminates TLS in one place instead of on the app server, and it
means I could add a second instance later without touching DNS or the app.

**Q: How does HTTPS work here?**
A: ACM issued a cert for my domain, validated through a DNS record Terraform created in Route 53
automatically. The ALB terminates TLS — the encrypted connection ends there, and traffic from the
ALB to EC2 is plain HTTP inside AWS's network. Port 80 redirects to 443 with a 301.

**Q: Tell me about a bug you actually ran into.**
A: I was allowlisting my home IP in the security group to test directly against the instance, and
`curl` kept timing out. Checked `curl ifconfig.me` twice and got a different address each time —
once IPv6, once a different IPv4. My home network doesn't have a stable public IPv4 address.
IP-based access control just wasn't going to work reliably for my situation, so instead of
patching around it I moved to the ALB, which doesn't care what IP the client has.

---

## CI/CD

**Q: What happens when you push code?**
A: GitHub Actions triggers on a push to `main` that touches `app/`. It gets a short-lived OIDC
token from GitHub, uses it to assume an AWS IAM role (no AWS keys stored in GitHub anywhere),
builds the Docker image, pushes it to ECR tagged with the commit SHA and `latest`, then uses SSM
Run Command to tell the EC2 instance to pull it and restart the container. Last step curls the
health endpoint to confirm it actually worked.

**Q: Why OIDC instead of storing AWS keys as a GitHub secret?**
A: Stored keys don't expire on their own — if one leaks, it's valid until someone manually rotates
it. OIDC tokens are minted per run and expire almost immediately, and AWS only trusts tokens whose
claims match my specific repo. There's no persistent secret to steal.

**Q: What was the hardest bug on this whole project?**
A: The OIDC role assumption started failing with an auth error a few days after I set it up. The
trust policy looked correct on paper. Instead of guessing, I pulled the actual
`AssumeRoleWithWebIdentity` events from CloudTrail, which show exactly what GitHub sent versus what
AWS checked. Turned out GitHub had rolled out a change days earlier — new repos get tokens with a
different subject format that embeds numeric owner/repo IDs, specifically so a renamed or deleted
repo can't accidentally inherit someone else's trust policy. Mine was written for the old format.
Updated it and it worked immediately. Takeaway: when something that should work doesn't, check
what's actually being sent before assuming your own config is wrong.

---

## Monitoring

**Q: How would you know if this went down?**
A: Five CloudWatch alarms — EC2 CPU, RDS CPU, RDS free storage, ALB 5xx count, ALB unhealthy
targets — all publishing to an SNS topic that emails me. There's also a dashboard showing request
volume, response codes, response time, and resource use in one place.

**Q: What's missing that a real team would want?**
A: Structured application logs, not just infra metrics — right now I only have container stdout.
Something like PagerDuty instead of raw email for actual on-call. And request tracing once there's
more than one service involved.

---

## Security / IAM

**Q: How'd you handle permissions?**
A: Two separate identities. The EC2 role can only use SSM, read one specific SSM parameter, and
pull from one specific ECR repo. The GitHub Actions role can push to that same ECR repo and send
SSM commands to that one instance, nothing more. My own CLI user had full admin while I was
building — faster to move that way — then I replaced it with a policy scoped to just the services
this project touches, once everything worked.

**Q: Why not just leave the admin access — isn't that easier?**
A: Easier short-term, but it means one leaked credential has access to my whole AWS account instead
of just this project. Scoping it down afterward is standard practice — you verify the narrower
policy actually works before you remove the broad one, so you don't lock yourself out.

---

## Cost

**Q: What does this cost to run?**
A: Free Tier for the first year — both instances get 750 free hours/month, RDS gets 20GB free
storage. Real recurring cost is the domain, about $16/year. After Free Tier expires, probably
$15-25/month for the two instances.

**Q: How'd you avoid a surprise bill?**
A: Set a zero-spend billing alarm before creating a single resource — emails me if anything gets
charged at all, even a penny. Also skipped the one networking piece with a real ongoing cost (NAT
Gateway) and stuck to Free Tier instance sizes the whole way through.

---

## "What would you do differently"

Have a real answer ready, not "nothing":
- Self-host Postgres on EC2 too, to compare the operational overhead against RDS
- A staging environment so deploys can be tested before hitting the live domain
- Application-level logging, not just infra metrics
- Auto Scaling Group instead of a single instance, now that the ALB already supports it
