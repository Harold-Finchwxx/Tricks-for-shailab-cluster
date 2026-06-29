#!/usr/bin/env bash
# 兼容旧命令：等价于 start_domestic_proxies.sh deepseek
exec bash "$(dirname "$0")/start_domestic_proxies.sh" deepseek "$@"
