#!/usr/bin/env bash
# 输出过滤：把看起来像密码 / 令牌的值换成 ***。半角「:」「=」和全角「：」「＝」都算分隔符。
#   some_command | tools/deploy/redact.sh
# 只是兜底：正确做法是密码只按文件路径传、永远不打印。
set -euo pipefail
exec perl -CSD -Mutf8 -pe '
  s/((?:密码|口令|令牌|password|passwd|pass|secret|token|apikey|api_key)[^:：=＝\n]{0,24}[:：=＝]\s*)\S.*$/$1***/ig;
  s/(Bearer\s+)[A-Za-z0-9._~+\/=-]+/$1***/g;
'
