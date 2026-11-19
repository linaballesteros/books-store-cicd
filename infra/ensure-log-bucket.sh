#!/usr/bin/env bash
set -euo pipefail

workspace=${TF_WORKSPACE:?Select a Terraform workspace}
case "$workspace" in
  staging|production) ;;
  *) printf 'Unsupported workspace: %s\n' "$workspace" >&2; exit 1 ;;
esac

region=${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}
account=$(aws sts get-caller-identity --no-cli-pager --query Account --output text)
bucket="bookstore-$workspace-$account-alb-logs"

# Academy denies the Object Lock API called by the Terraform bucket resource.
# Create the bucket here and let Terraform manage its security and log delivery.
if status=$(aws s3api head-bucket --no-cli-pager --region "$region" \
  --bucket "$bucket" --expected-bucket-owner "$account" 2>&1); then
  exit 0
fi
if [[ "$status" != *"(404)"* ]]; then
  printf '%s\n' "$status" >&2
  exit 1
fi

if [[ "$region" == us-east-1 ]]; then
  aws s3api create-bucket --no-cli-pager --region "$region" --bucket "$bucket" >/dev/null
else
  aws s3api create-bucket --no-cli-pager --region "$region" --bucket "$bucket" \
    --create-bucket-configuration "LocationConstraint=$region" >/dev/null
fi
