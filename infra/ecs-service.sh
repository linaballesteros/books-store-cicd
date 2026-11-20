# Shared by application deployment and rollback.
active_revision() {
  aws ecs describe-services --region "$region" --no-cli-pager \
    --cluster "$cluster" --services "$service" --query 'services[0].taskDefinition' --output text
}

activate_revision() {
  local revision=$1 active
  printf 'Deploying %s\n' "$revision"
  aws ecs update-service --region "$region" --no-cli-pager --cluster "$cluster" \
    --service "$service" --task-definition "$revision" --desired-count 1 \
    --query 'service.serviceName' --output text || return
  aws ecs wait services-stable --region "$region" --cluster "$cluster" --services "$service" || return

  active=$(active_revision) || return
  if [[ "$active" != "$revision" ]]; then
    printf 'Expected %s but ECS stabilized on %s\n' "$revision" "$active" >&2
    return 1
  fi
  printf 'Application revision is stable.\n'
}
