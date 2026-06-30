#!/usr/bin/env bash
#
# teardown.sh — Remove everything deploy.sh created, in the right order.
#
# CloudFront requires a distribution to be *disabled* and fully propagated
# before it can be deleted, so this script disables it, waits, then deletes.
# The wait can take 5-15 minutes — that's CloudFront, not the script hanging.
#
# Usage:  ./scripts/teardown.sh

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

require_tools

load_state || die "No ${STATE_FILE} found. Nothing to tear down."

log "About to delete:"
echo "    S3 bucket:    ${BUCKET}"
echo "    Distribution: ${DISTRIBUTION_ID} (${DISTRIBUTION_DOMAIN})"
echo "    OAC:          ${OAC_ID}"
read -r -p "Type 'delete' to confirm: " CONFIRM
[[ "${CONFIRM}" == "delete" ]] || die "Aborted."

# --- 1. Disable the distribution (if still enabled) --------------------------
log "Fetching current distribution config ..."
TMP_CFG="$(mktemp)"
trap 'rm -f "${TMP_CFG}" "${TMP_CFG}.new"' EXIT

ETAG="$(aws cloudfront get-distribution-config --id "${DISTRIBUTION_ID}" \
  --query 'ETag' --output text)"
aws cloudfront get-distribution-config --id "${DISTRIBUTION_ID}" \
  --query 'DistributionConfig' > "${TMP_CFG}"

if [[ "$(jq -r '.Enabled' "${TMP_CFG}")" == "true" ]]; then
  log "Disabling distribution ${DISTRIBUTION_ID} ..."
  jq '.Enabled = false' "${TMP_CFG}" > "${TMP_CFG}.new"
  ETAG="$(aws cloudfront update-distribution --id "${DISTRIBUTION_ID}" \
    --distribution-config "file://${TMP_CFG}.new" \
    --if-match "${ETAG}" --query 'ETag' --output text)"
  ok "Disable requested."
else
  ok "Distribution already disabled."
fi

log "Waiting for the distribution to finish deploying (this is the slow part) ..."
aws cloudfront wait distribution-deployed --id "${DISTRIBUTION_ID}"

# --- 2. Delete the distribution ----------------------------------------------
log "Deleting distribution ${DISTRIBUTION_ID} ..."
aws cloudfront delete-distribution --id "${DISTRIBUTION_ID}" --if-match "${ETAG}"
ok "Distribution deleted."

# --- 3. Delete the OAC -------------------------------------------------------
log "Deleting Origin Access Control ${OAC_ID} ..."
OAC_ETAG="$(aws cloudfront get-origin-access-control --id "${OAC_ID}" \
  --query 'ETag' --output text)"
aws cloudfront delete-origin-access-control --id "${OAC_ID}" --if-match "${OAC_ETAG}"
ok "OAC deleted."

# --- 4. Empty + delete the bucket --------------------------------------------
log "Emptying and deleting bucket ${BUCKET} ..."
aws s3 rm "s3://${BUCKET}/" --recursive >/dev/null
aws s3api delete-bucket --bucket "${BUCKET}"
ok "Bucket deleted."

rm -f "${STATE_FILE}"
ok "Teardown complete. ${STATE_FILE} removed."
