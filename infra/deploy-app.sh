#!/usr/bin/env bash
set -euo pipefail

infra_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
region=$(terraform -chdir="$infra_dir" output -raw aws_region)
cluster=$(terraform -chdir="$infra_dir" output -raw ecs_cluster_name)
service=$(terraform -chdir="$infra_dir" output -raw ecs_service_name)
revision=$(terraform -chdir="$infra_dir" output -raw app_task_definition_arn)

source "$infra_dir/ecs-service.sh"
activate_revision "$revision"
