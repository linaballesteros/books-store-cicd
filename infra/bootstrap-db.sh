#!/usr/bin/env bash
set -euo pipefail

infra_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
region=$(terraform -chdir="$infra_dir" output -raw aws_region)
cluster=$(terraform -chdir="$infra_dir" output -raw ecs_cluster_name)
task_input=$(terraform -chdir="$infra_dir" output -json bootstrap_task)

task=$(aws ecs run-task --region "$region" --no-cli-pager \
  --cli-input-json "$task_input" --output text \
  --query 'tasks[0].taskArn || failures[0].reason')

if [[ "$task" != arn:* ]]; then
  printf 'Database bootstrap task could not start: %s\n' "$task" >&2
  exit 1
fi

printf 'Waiting for database bootstrap task %s\n' "$task"
aws ecs wait tasks-stopped --region "$region" --cluster "$cluster" --tasks "$task"

read -r exit_code reason < <(aws ecs describe-tasks --region "$region" --no-cli-pager \
  --cluster "$cluster" --tasks "$task" --output text \
  --query 'tasks[0].[containers[?name==`bootstrap`].exitCode | [0], stoppedReason]')

if [[ "$exit_code" != 0 ]]; then
  printf 'Database bootstrap failed (exit code %s): %s\n' "$exit_code" "$reason" >&2
  exit 1
fi

printf 'Database bootstrap completed successfully.\n'
