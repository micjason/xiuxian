#!/usr/bin/env bash
# 把服务器上的 admin-credentials（「后台管理员账号：x」「后台管理员密码：y」，冒号可能是全角「：」或半角「:」）
# 转成 KEY=VALUE（ADMIN_USER / ADMIN_PASS / ADMIN_URL）。从标准输入读、写到标准输出，调用方负责重定向到 0600 文件。
set -euo pipefail
exec perl -CSD -Mutf8 -ne '
  s/\r?\n$//;
  next unless /^([^:：]*)[:：]\s*(.*?)\s*$/;
  my ($k, $v) = ($1, $2);
  if ($k =~ /账号/) { print "ADMIN_USER=$v\n" }
  elsif ($k =~ /密码/) { print "ADMIN_PASS=$v\n" }
  elsif ($k =~ /网址/) { print "ADMIN_URL=$v\n" }
'
