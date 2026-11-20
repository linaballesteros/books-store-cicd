#!/usr/bin/env bash
set -euo pipefail

infra_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$infra_dir/ecs-service.sh"

workspace=${TF_WORKSPACE:?Select a Terraform workspace}
case "$workspace" in
  staging|production) ;;
  *) printf 'Unsupported workspace: %s\n' "$workspace" >&2; exit 1 ;;
esac
region=${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}
cluster="bookstore-$workspace"
service=$cluster
parameter="/bookstore/$workspace/deployment/validated-revisions"

history=$(aws ssm get-parameters --region "$region" --no-cli-pager --names "$parameter" \
  --query 'Parameters[0].Value' --output text)
last_good=
previous_good=
if [[ "$history" != None ]]; then
  IFS=, read -r last_good previous_good <<< "$history"
fi

record_revision() {
  local revision=$1 previous=$2
  aws ssm put-parameter --region "$region" --no-cli-pager --name "$parameter" \
    --type String --value "$revision${previous:+,$previous}" --overwrite >/dev/null
  printf 'Recorded validated revision %s\n' "$revision"
}

smoke() {
  python3 "$infra_dir/smoke-test.py" "$application_url"
}

application_url=${APPLICATION_URL:-}
if [[ -z "$application_url" ]]; then
  application_url=$(aws apigatewayv2 get-apis --region "$region" --no-cli-pager \
    --query "Items[?Name=='$service'].ApiEndpoint" --output text)
fi
if [[ ! "$application_url" =~ ^https://[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com$ ]]; then
  printf 'Expected exactly one API Gateway HTTPS endpoint for %s\n' "$workspace" >&2
  exit 1
fi

active=$(active_revision)
target=$last_good
remaining=$previous_good
if [[ "$active" == "$last_good" ]]; then
  target=$previous_good
  remaining=
fi

require_candidate() {
  local candidate=$1
  if [[ "$active" != "$candidate" ]]; then
    printf 'Expected candidate %s but found %s\n' "$candidate" "$active" >&2
    exit 1
  fi
}

record_candidate() {
  if [[ "$active" != "$last_good" ]]; then
    record_revision "$active" "$last_good"
  fi
}

restore_target() {
  if [[ -z "$target" ]]; then
    printf 'There is no different validated revision to restore.\n' >&2
    return 1
  fi
  activate_revision "$target"
  smoke
}

recover_candidate() {
  printf 'Release validation failed.\n' >&2
  restore_target
  if [[ "$active" == "$last_good" ]]; then
    record_revision "$target" "$remaining"
  fi
  printf 'Recovery smoke tests passed. The candidate still failed validation.\n'
}

case "${1:-}" in
  record) require_candidate "${2:?Expected ECS task definition ARN}"; record_candidate ;;
  recover) require_candidate "${2:?Expected ECS task definition ARN}"; recover_candidate ;;
  verify)
    require_candidate "${2:?Expected ECS task definition ARN}"
    if smoke; then
      record_candidate
    else
      recover_candidate
      exit 1
    fi
    ;;
  rollback)
    restore_target
    record_revision "$target" "$remaining"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      printf 'application_url=%s\n' "$application_url" >> "$GITHUB_OUTPUT"
    fi
    ;;
  *) printf 'Use verify, record or recover <task-definition-arn>, or rollback.\n' >&2; exit 1 ;;
esac
