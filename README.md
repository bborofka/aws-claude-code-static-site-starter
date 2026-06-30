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
└── CLAUDE.md              # guidance for Claude Code
```

## Prerequisites

- An AWS account, with credentials the AWS CLI can use (a scoped deploy profile
  is recommended — see [Scoped deploy profile (optional)](#scoped-deploy-profile-optional))
- [AWS CLI v2](https://aws.amazon.com/cli/)
- [`jq`](https://jqlang.github.io/jq/) (`brew install jq`) — used to build and
  edit the JSON the AWS CLI sends for CloudFront and the bucket policy

## Quick start

1. **Set up AWS credentials.** Any credentials the AWS CLI can use will work.
   Recommended: a scoped deploy profile that limits Claude Code to S3 and
   CloudFront for this project — see
   [Scoped deploy profile (optional)](#scoped-deploy-profile-optional).

2. **Configure the project** — copy the example config and set `PROJECT_NAME`,
   `AWS_REGION`, and `AWS_PROFILE`:

   ```bash
   cp config.example.sh config.sh
   ```

3. **Deploy:**

   ```bash
   ./scripts/deploy.sh
   ```

   It prints your live URL, e.g. `https://d1234abcd.cloudfront.net`.

The first deploy provisions the bucket, OAC, distribution, and bucket policy,
then uploads `site/`. CloudFront takes a few minutes to propagate worldwide the
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

## Scoped deploy profile (optional)

The scripts work with whatever credentials the AWS CLI is configured to use. But
the point of this starter is that you (and Claude Code) can deploy with
credentials that can **only** touch S3 and CloudFront for this project — not
your whole AWS account. This one-time setup creates that scoped profile.

### 1. Create an IAM user with the scoped policy

The policy lives at [`iam/deploy-policy.json`](iam/deploy-policy.json). It allows:

- `sts:GetCallerIdentity` — so the script can find your account ID
- S3 actions, limited to buckets named `my-static-site-*`
- CloudFront actions needed to create/update/delete a distribution + OAC

> **Heads up:** the S3 resource ARNs are hard-coded to the `my-static-site-*`
> prefix. If you change `PROJECT_NAME` in your config, update the two
> `arn:aws:s3:::my-static-site-*` lines in the policy to match.
>
> CloudFront actions can't be scoped to a single distribution at create time,
> so those are `"Resource": "*"`. That's expected and is still far narrower
> than account-wide admin.

```bash
aws iam create-policy \
  --policy-name static-site-deployer \
  --policy-document file://iam/deploy-policy.json

aws iam create-user --user-name static-site-deployer

aws iam attach-user-policy \
  --user-name static-site-deployer \
  --policy-arn "arn:aws:iam::<YOUR_ACCOUNT_ID>:policy/static-site-deployer"

aws iam create-access-key --user-name static-site-deployer
```

That last command prints an `AccessKeyId` and `SecretAccessKey`. Save them for
the next step.

### 2. Store the credentials as a named CLI profile

```bash
aws configure --profile static-site-deployer
# AWS Access Key ID:     <from step 1>
# AWS Secret Access Key: <from step 1>
# Default region name:   us-east-1
# Default output format:  json
```

### 3. Point the project at that profile

Set `AWS_PROFILE="static-site-deployer"` in your `config.sh`. Now
`./scripts/deploy.sh` only ever acts through that scoped profile — if you let
Claude Code run the deploy, the blast radius is limited to this project's S3
buckets and CloudFront distributions.

### Cleaning up the IAM bits later

```bash
aws iam list-access-keys --user-name static-site-deployer   # find the key id
aws iam delete-access-key --user-name static-site-deployer --access-key-id <id>
aws iam detach-user-policy --user-name static-site-deployer \
  --policy-arn "arn:aws:iam::<YOUR_ACCOUNT_ID>:policy/static-site-deployer"
aws iam delete-user --user-name static-site-deployer
aws iam delete-policy --policy-arn "arn:aws:iam::<YOUR_ACCOUNT_ID>:policy/static-site-deployer"
```

## Cost

For a low-traffic static site this is typically **pennies per month** — S3
storage for a few small files plus CloudFront requests/transfer, much of which
can fall in the AWS Free Tier. Always check current AWS pricing for your usage.

## How it works

Every step below is a plain AWS CLI command (`aws s3 ...`, `aws cloudfront ...`)
issued by [`scripts/deploy.sh`](scripts/deploy.sh) under whatever profile your
config selects. If you set up the optional scoped profile, the CLI authenticates
as that IAM user via `AWS_PROFILE`, so each `aws` call is signed with
credentials that can only act on this project's S3 and CloudFront resources —
nothing in the scripts runs outside that boundary.

1. **S3 bucket** is created private, with S3 Block Public Access fully enabled.
   This is AWS's recommended best practice — the bucket is never directly
   reachable from the internet; only CloudFront can read from it (step 2).
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
