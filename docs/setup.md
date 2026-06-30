# Setup: a scoped AWS CLI profile for deploys

The whole point of this starter is that you (and Claude Code) can deploy with
credentials that can **only** touch S3 and CloudFront for this project — not
your whole AWS account. Here's the one-time setup.

## 1. Create an IAM user (or role) with the scoped policy

The policy lives at [`iam/deploy-policy.json`](../iam/deploy-policy.json). It allows:

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

Create the policy and a user:

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

## 2. Store the credentials as a named CLI profile

```bash
aws configure --profile static-site-deployer
# AWS Access Key ID:     <from step 1>
# AWS Secret Access Key: <from step 1>
# Default region name:   us-east-1
# Default output format:  json
```

## 3. Point the project at that profile

```bash
cp config.example.sh config.sh
# edit config.sh — set AWS_PROFILE="static-site-deployer"
```

Now `./scripts/deploy.sh` only ever acts through that scoped profile. If you
let Claude Code run the deploy, the blast radius is limited to this project's
S3 buckets and CloudFront distributions.

## Cleaning up the IAM bits later

```bash
aws iam list-access-keys --user-name static-site-deployer   # find the key id
aws iam delete-access-key --user-name static-site-deployer --access-key-id <id>
aws iam detach-user-policy --user-name static-site-deployer \
  --policy-arn "arn:aws:iam::<YOUR_ACCOUNT_ID>:policy/static-site-deployer"
aws iam delete-user --user-name static-site-deployer
aws iam delete-policy --policy-arn "arn:aws:iam::<YOUR_ACCOUNT_ID>:policy/static-site-deployer"
```
