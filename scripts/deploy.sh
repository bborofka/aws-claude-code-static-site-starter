#!/usr/bin/env bash
#
# deploy.sh — Put the contents of ./site online as an HTTPS static site.
#
# What it creates (once), then reuses on every later run:
#   1. A private Amazon S3 bucket (Block Public Access stays ON).
#   2. A CloudFront Origin Access Control (OAC) so only CloudFront can read it.
#   3. A CloudFront distribution serving the bucket over HTTPS.
#   4. A bucket policy granting that one distribution read access.
#
# On re-runs it just syncs ./site and invalidates the CloudFront cache.
#
# Usage:  ./scripts/deploy.sh
# Config: PROJECT_NAME, AWS_REGION, AWS_PROFILE (see config.example.sh)

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# AWS-managed "CachingOptimized" cache policy (stable, well-known ID).
MANAGED_CACHE_POLICY_ID="658327ea-f89d-4fab-a63d-7e88639e58f6"

require_tools
require_valid_project_name

[[ -f "${SITE_DIR}/index.html" ]] || die "No ${SITE_DIR}/index.html found — nothing to deploy."

# -----------------------------------------------------------------------------
# Already provisioned? Just push the latest files and invalidate the cache.
# -----------------------------------------------------------------------------
if load_state; then
  log "Existing deployment found (bucket: ${BUCKET})."
  log "Syncing ${SITE_DIR} → s3://${BUCKET} ..."
  aws s3 sync "${SITE_DIR}/" "s3://${BUCKET}/" --delete
  log "Invalidating CloudFront cache ..."
  aws cloudfront create-invalidation --distribution-id "${DISTRIBUTION_ID}" --paths '/*' >/dev/null
  ok "Updated. Live at: https://${DISTRIBUTION_DOMAIN}"
  exit 0
fi

# -----------------------------------------------------------------------------
# First-time provisioning.
# -----------------------------------------------------------------------------
log "Resolving AWS account ..."
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" \
  || die "Could not call AWS. Check your credentials / AWS_PROFILE."
BUCKET="$(bucket_name "${ACCOUNT_ID}")"
ok "Account ${ACCOUNT_ID}, region ${AWS_REGION}, bucket ${BUCKET}"

# --- 1. Private S3 bucket -----------------------------------------------------
log "Creating private S3 bucket: ${BUCKET}"
if [[ "${AWS_REGION}" == "us-east-1" ]]; then
  # us-east-1 rejects a LocationConstraint; every other region requires one.
  aws s3api create-bucket --bucket "${BUCKET}" >/dev/null
else
  aws s3api create-bucket --bucket "${BUCKET}" \
    --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
fi

aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
ok "Bucket created and locked down."

# --- 2. Origin Access Control -------------------------------------------------
log "Creating CloudFront Origin Access Control ..."
OAC_ID="$(aws cloudfront create-origin-access-control \
  --origin-access-control-config "$(jq -nc \
    --arg name "${PROJECT_NAME}-oac" \
    '{Name:$name, SigningProtocol:"sigv4", SigningBehavior:"always", OriginAccessControlOriginType:"s3"}')" \
  --query 'OriginAccessControl.Id' --output text)"
ok "OAC ${OAC_ID}"

# --- 3. CloudFront distribution ----------------------------------------------
log "Creating CloudFront distribution (this is quick; propagation takes a few minutes) ..."
ORIGIN_DOMAIN="${BUCKET}.s3.${AWS_REGION}.amazonaws.com"
CALLER_REF="${PROJECT_NAME}-$(aws sts get-caller-identity --query UserId --output text | tr -dc 'A-Za-z0-9')-${BUCKET}"

DIST_CONFIG="$(jq -nc \
  --arg ref "${CALLER_REF}" \
  --arg comment "${PROJECT_NAME} static site" \
  --arg origin "${ORIGIN_DOMAIN}" \
  --arg oac "${OAC_ID}" \
  --arg cache "${MANAGED_CACHE_POLICY_ID}" \
  '{
    CallerReference: $ref,
    Comment: $comment,
    Enabled: true,
    DefaultRootObject: "index.html",
    Origins: { Quantity: 1, Items: [ {
      Id: "s3-origin",
      DomainName: $origin,
      OriginAccessControlId: $oac,
      S3OriginConfig: { OriginAccessIdentity: "" }
    } ] },
    DefaultCacheBehavior: {
      TargetOriginId: "s3-origin",
      ViewerProtocolPolicy: "redirect-to-https",
      Compress: true,
      CachePolicyId: $cache,
      AllowedMethods: { Quantity: 2, Items: ["GET","HEAD"],
        CachedMethods: { Quantity: 2, Items: ["GET","HEAD"] } }
    },
    CustomErrorResponses: { Quantity: 1, Items: [ {
      ErrorCode: 403, ResponseCode: "404",
      ResponsePagePath: "/error.html", ErrorCachingMinTTL: 10
    } ] },
    PriceClass: "PriceClass_100"
  }')"

DISTRIBUTION_ID="$(aws cloudfront create-distribution \
  --distribution-config "${DIST_CONFIG}" \
  --query 'Distribution.Id' --output text)"
DISTRIBUTION_DOMAIN="$(aws cloudfront get-distribution \
  --id "${DISTRIBUTION_ID}" --query 'Distribution.DomainName' --output text)"
ok "Distribution ${DISTRIBUTION_ID} (${DISTRIBUTION_DOMAIN})"

# --- 4. Bucket policy: allow only this distribution --------------------------
log "Granting the distribution read access to the bucket ..."
aws s3api put-bucket-policy --bucket "${BUCKET}" --policy "$(jq -nc \
  --arg bucket "${BUCKET}" \
  --arg arn "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}" \
  '{
    Version: "2012-10-17",
    Statement: [ {
      Sid: "AllowCloudFrontServicePrincipalReadOnly",
      Effect: "Allow",
      Principal: { Service: "cloudfront.amazonaws.com" },
      Action: "s3:GetObject",
      Resource: ("arn:aws:s3:::" + $bucket + "/*"),
      Condition: { StringEquals: { "AWS:SourceArn": $arn } }
    } ]
  }')"
ok "Bucket policy applied."

# --- Upload + persist state --------------------------------------------------
log "Uploading ${SITE_DIR} → s3://${BUCKET} ..."
aws s3 sync "${SITE_DIR}/" "s3://${BUCKET}/" --delete

save_state
ok "State saved to ${STATE_FILE}"

echo
ok "Deployed! Your site will be live at:"
echo "    https://${DISTRIBUTION_DOMAIN}"
echo
log "First-time note: CloudFront takes a few minutes to finish deploying"
log "the distribution worldwide. If you get an error at first, wait and retry."
