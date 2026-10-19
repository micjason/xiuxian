#!/usr/bin/env bash
# 回到上一版：DEPLOY_HOST=101.132.74.32 tools/deploy/rollback.sh [--with-db --yes]
# 等于 deploy.sh rollback。默认只换代码和后台网页，不动数据库；见 server/rollback.sh。
exec "$(cd "$(dirname "$0")" && pwd)/deploy.sh" rollback "$@"
