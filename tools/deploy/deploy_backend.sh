#!/bin/sh
set -eu
ENV_NAME="${1:-staging}"
GIT_TAG="${2:-}"
if [ -z "$GIT_TAG" ]; then
  echo "usage: deploy_backend.sh <staging|prod> <git-tag>" >&2
  exit 1
fi
echo "准备部署 $ENV_NAME $GIT_TAG。正式切换、备案和 HTTPS 由项目负责人执行，此脚本只打印步骤。"
echo "1. git fetch && git checkout $GIT_TAG"
echo "2. cd backend && npm ci && npm test && npm run db:migrate"
echo "3. systemctl restart xiuxian-api-$ENV_NAME"
echo "4. curl -fsS http://127.0.0.1:8080/healthz"
