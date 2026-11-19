#!/usr/bin/env bash
set -euo pipefail

infra_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
region=$(terraform -chdir="$infra_dir" output -raw aws_region)
cluster=$(terraform -chdir="$infra_dir" output -raw ecs_cluster_name)
service=$(terraform -chdir="$infra_dir" output -raw ecs_service_name)
revision=$(terraform -chdir="$infra_dir" output -raw app_task_definition_arn)

printf 'Deploying %s\n' "$revision"
aws ecs update-service --region "$region" --no-cli-pager --cluster "$cluster" \
  --service "$service" --task-definition "$revision" --desired-count 1 \
  --query 'service.serviceName' --output text
aws ecs wait services-stable --region "$region" --cluster "$cluster" --services "$service"

active_revision=$(aws ecs describe-services --region "$region" --no-cli-pager \
  --cluster "$cluster" --services "$service" --query 'services[0].taskDefinition' --output text)
if [[ "$active_revision" != "$revision" ]]; then
  printf 'Expected %s but ECS stabilized on %s\n' "$revision" "$active_revision" >&2
  exit 1
fi

printf 'Application revision is stable.\n'
