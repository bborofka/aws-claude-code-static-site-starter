# aws-claude-code-static-site-starter

A minimal starter for taking a prototype from `localhost` to a shareable HTTPS
URL with Claude Code and the AWS CLI — a private S3 bucket served over
CloudFront, deployed in minutes.

```text
Claude Code  →  AWS CLI  →  Amazon S3 (private)  →  Amazon CloudFront (HTTPS)
```

With a bit of one-time setup and a **scoped AWS CLI profile**, Claude Code can
build a site and deploy the AWS resources for it — HTTPS, edge caching, and
often pennies per month. Good enough for demos, landing pages, internal tools,
and proof-of-concept projects.

---

## What you get

A private S3 bucket served over HTTPS through CloudFront using **Origin Access
Control (OAC)** — the current AWS best practice. No public buckets, no
certificates to manage (you get HTTPS on the default `*.cloudfront.net` URL out
of the box).

```text
.
├── site/                  # your static files (edit these)
│   ├── index.html
│   ├── error.html
│   └── styles.css
├── scripts/
│   ├── deploy.sh          # provision once, then sync + invalidate
│   ├── teardown.sh        # delete everything it created
│   └── _common.sh         # shared helpers
├── iam/deploy-policy.json # least-privilege policy for the deploy profile
├── config.example.sh      # copy to config.sh
├── CLAUDE.md              # guidance for Claude Code
└── docs/setup.md          # scoped AWS CLI profile setup
```

## Prerequisites

- An AWS account
- [AWS CLI v2](https://aws.amazon.com/cli/)
- [`jq`](https://jqlang.github.io/jq/) (`brew install jq`)

## Quick start

```bash
# 1. One-time: create a scoped deploy profile (see docs/setup.md)
#    This gives Claude Code credentials limited to S3 + CloudFront for this project.

# 2. Configure the project
cp config.example.sh config.sh
#    edit config.sh: set PROJECT_NAME, AWS_REGION, AWS_PROFILE

# 3. Deploy
./scripts/deploy.sh
#    prints:  https://d1234abcd.cloudfront.net
```

First deploy provisions the bucket, OAC, distribution, and bucket policy, then
uploads `site/`. CloudFront takes a few minutes to propagate worldwide the
first time — if the URL errors at first, wait a moment and retry.

## Update your site

Edit anything in `site/`, then:

```bash
./scripts/deploy.sh   # syncs files and invalidates the CloudFront cache
```

Re-running is **idempotent** — it reuses the existing infrastructure (tracked
in the git-ignored `.deploy-state` file) and just pushes the new files.

## Tear it down

```bash
./scripts/teardown.sh
```

This disables the distribution, waits for CloudFront to propagate (5–15 min —
that's normal), then deletes the distribution, OAC, and bucket.

## Why a scoped profile?

So you can hand the keys to an AI agent without handing over your account. The
[`iam/deploy-policy.json`](iam/deploy-policy.json) policy only allows S3 actions
on `my-static-site-*` buckets plus the CloudFront actions these scripts need.
Full walkthrough in [docs/setup.md](docs/setup.md).

## Cost

For a low-traffic static site this is typically **pennies per month** — S3
storage for a few small files plus CloudFront requests/transfer, much of which
can fall in the AWS Free Tier. Always check current AWS pricing for your usage.

## How it works

1. **S3 bucket** is created private, with Block Public Access fully on.
2. A **CloudFront Origin Access Control (OAC)** lets only CloudFront read it.
3. A **CloudFront distribution** serves the bucket over HTTPS, redirects HTTP
   to HTTPS, compresses responses, and uses the AWS-managed CachingOptimized
   policy.
4. A **bucket policy** grants `s3:GetObject` to the CloudFront service
   principal, scoped to that one distribution's ARN.
5. Your files are uploaded with `aws s3 sync`.

## Going further

This repo stays deliberately minimal — raw AWS CLI calls you can read top to
bottom, scoped to a single static site. When you outgrow that and want broad,
agent-driven AWS coverage (multi-service apps, CDK, Bedrock agents, and more),
see the official [Agent Toolkit for AWS](https://github.com/aws/agent-toolkit-for-aws):
an MCP server and plugins that give Claude Code access to 300+ AWS services.

## License

MIT — see [LICENSE](LICENSE).
