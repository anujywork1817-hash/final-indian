#!/usr/bin/env bash
# Builds all 5 Go services locally (using docker-compose.dev.yml's build
# contexts) and pushes them to ECR as :latest, tagged with the git commit
# short SHA too for rollback/traceability.
#
# Run this whenever backend Go code changes, BEFORE `eb deploy` —
# `eb deploy` only ships docker-compose.yml (which just references these
# image tags); it does not rebuild them.
#
# Usage: ./scripts/build-and-push.sh   (from kumbh_backend/)
set -euo pipefail
cd "$(dirname "$0")/.."

REGION="ap-south-1"
ACCOUNT_ID="821279529027"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
SERVICES=(api-gateway auth-service tent-service booking-service payment-service)
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")

echo "== Logging in to ECR ($REGISTRY) =="
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo "== Building all services (docker-compose.dev.yml) =="
docker compose -f docker-compose.dev.yml build "${SERVICES[@]}"

for svc in "${SERVICES[@]}"; do
  repo="$REGISTRY/bharat-tent/$svc"
  local_image="kumbh_backend-$svc:latest"
  # docker-compose.dev.yml names built images kumbh_backend-<service>
  # unless COMPOSE_PROJECT_NAME overrides it — adjust if your project
  # name differs.
  echo "== Tagging and pushing $svc =="
  docker tag "$local_image" "$repo:latest"
  docker tag "$local_image" "$repo:$SHA"
  docker push "$repo:latest"
  docker push "$repo:$SHA"
done

echo
echo "Done. Pushed :latest and :$SHA for: ${SERVICES[*]}"
echo "Now run: eb deploy bharat-tent-api-alb"
