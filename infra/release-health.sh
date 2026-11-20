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

verify_candidate() {
  smoke || return
  if [[ "${1:-}" == "acceptance" ]]; then
    if [[ "${ACCEPTANCE_BROWSER_STATUS:-success}" != "success" ]]; then
      printf 'The acceptance browser failed to install.\n' >&2
      return 1
    fi
    npm --prefix "$infra_dir/e2e" test
  fi
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
case "${1:-}" in
  verify)
    candidate=${2:?Expected ECS task definition ARN}
    if [[ "$active" != "$candidate" ]]; then
      printf 'Expected candidate %s but found %s\n' "$candidate" "$active" >&2
      exit 1
    fi
    if verify_candidate "${3:-}"; then
      if [[ "$active" != "$last_good" ]]; then
        record_revision "$active" "$last_good"
      fi
    else
      if [[ -z "$target" ]]; then
        printf 'Release validation failed and there is no different validated revision to restore.\n' >&2
      else
        printf 'Release validation failed. Restoring %s.\n' "$target" >&2
        activate_revision "$target"
        smoke
        if [[ "$active" == "$last_good" ]]; then
          record_revision "$target" "$remaining"
        fi
        printf 'Recovery smoke tests passed. The candidate still failed validation.\n'
      fi
      exit 1
    fi
    ;;
  rollback)
    if [[ -z "$target" ]]; then
      printf 'There is no different validated revision to restore.\n' >&2
      exit 1
    fi
    activate_revision "$target"
    smoke
    record_revision "$target" "$remaining"
    ;;
  *) printf 'Use verify <task-definition-arn> or rollback.\n' >&2; exit 1 ;;
esac
