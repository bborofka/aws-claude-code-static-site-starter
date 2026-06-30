# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this project is

A minimal starter for shipping a **static site** from localhost to a real
HTTPS URL on AWS, using only the AWS CLI. The flow is:

> Claude Code → AWS CLI → Amazon S3 (private) → Amazon CloudFront (HTTPS)

The site is hosted in a private S3 bucket and served through CloudFront with
**Origin Access Control (OAC)** — there are no public buckets.

## Layout

- `site/` — the static files that get deployed. Edit `index.html` etc. here.
- `scripts/deploy.sh` — provisions infra on first run, then syncs + invalidates.
- `scripts/teardown.sh` — deletes everything it created (slow: CloudFront).
- `scripts/_common.sh` — shared config/state helpers (sourced, not run).
- `iam/deploy-policy.json` — least-privilege policy for the deploy profile.
- `config.example.sh` — copy to `config.sh` (git-ignored) to set name/region/profile.
- `.deploy-state` — generated; records bucket + distribution IDs. Git-ignored.

## How to work here

- **To change the site:** edit files under `site/`, then run `./scripts/deploy.sh`.
- **Deploys are idempotent.** If `.deploy-state` exists, deploy.sh only syncs
  files and invalidates the cache — it does not recreate infrastructure.
- **Never commit** `config.sh` or `.deploy-state` (already in `.gitignore`).
- **Use the scoped profile.** Deploys should run through the `AWS_PROFILE` set
  in `config.sh`, not account-admin credentials. See `docs/setup.md`.
- **Prereqs:** AWS CLI v2 and `jq` must be installed.

## Guardrails

- Don't widen the IAM policy or make the S3 bucket public to "make it work."
  If a deploy fails, fix the script or the policy scope — keep the bucket private.
- Before running `teardown.sh`, confirm with the user — it deletes the bucket
  and distribution.
- The CloudFront cache-policy ID and OAC config in `deploy.sh` are deliberate;
  don't swap them for legacy Origin Access Identity (OAI) or `ForwardedValues`.
