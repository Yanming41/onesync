#!/bin/zsh
# 开发调试：在 GUI 会话里用 OneSync 读到的配置/钥匙串密码跑 rclone（SSH 会话读不到登录钥匙串）
# 用法：scripts/rc.sh listremotes
O=$(mktemp); open -n -W --stdout $O --stderr $O ~/Applications/OneSync.app --args --rclone "$@"; cat $O; rm -f $O
