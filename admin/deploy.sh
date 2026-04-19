#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

(cd ../aws-email && terraform output -json) > /tmp/buba-tf-output.json

API_BASE=$(jq -r '.api_base_url.value' /tmp/buba-tf-output.json)
COGNITO_DOMAIN=$(jq -r '.cognito_hosted_ui_domain.value' /tmp/buba-tf-output.json)
CLIENT_ID=$(jq -r '.cognito_client_id.value' /tmp/buba-tf-output.json)
ADMIN_SITE=$(jq -r '.admin_site_url.value' /tmp/buba-tf-output.json)
BUCKET=$(jq -r '.admin_s3_bucket.value' /tmp/buba-tf-output.json)
CF_DIST=$(jq -r '.cloudfront_admin_distribution_id.value' /tmp/buba-tf-output.json)

for v in API_BASE COGNITO_DOMAIN CLIENT_ID ADMIN_SITE BUCKET CF_DIST; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    echo "Missing terraform output for $v" >&2
    exit 1
  fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

rsync -a --exclude deploy.sh --exclude '*.bak' ./ "$tmp/"

sed -i.bak \
  "s|__API_BASE__|$API_BASE|g; s|__COGNITO_DOMAIN__|$COGNITO_DOMAIN|g; s|__COGNITO_CLIENT_ID__|$CLIENT_ID|g; s|__REDIRECT_URI__|$ADMIN_SITE/callback.html|g" \
  "$tmp/config.js"
rm -f "$tmp/config.js.bak"

aws s3 sync "$tmp/" "s3://$BUCKET/" --delete --cache-control "public, max-age=300"
aws cloudfront create-invalidation --distribution-id "$CF_DIST" --paths '/*' > /dev/null

echo "Deployed. Visit $ADMIN_SITE"
