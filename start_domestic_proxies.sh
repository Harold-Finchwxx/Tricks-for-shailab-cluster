#!/usr/bin/env bash
# 启动国产模型 Responses 桥接（全部或指定 provider）
# 用法:
#   start_domestic_proxies.sh           # 启动所有已配置 Key 的 provider
#   start_domestic_proxies.sh qwen glm  # 仅启动指定 provider

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${SCRIPT_DIR}/domestic_models.conf"
LAUNCHER="${SCRIPT_DIR}/start_codex_responses_proxy.sh"

if [[ ! -f "$CONF" ]]; then
  echo "错误: 找不到 ${CONF}" >&2
  exit 1
fi

targets=("$@")
started=0
skipped=0

while IFS='|' read -r provider port upstream key_env _comment; do
  [[ -z "$provider" || "$provider" =~ ^# ]] && continue
  if ((${#targets[@]} > 0)); then
    match=0
    for t in "${targets[@]}"; do
      [[ "$t" == "$provider" ]] && match=1 && break
    done
    (( match == 0 )) && continue
  fi
  if bash "$LAUNCHER" "$provider" "$port" "$upstream" "$key_env"; then
    started=$((started + 1))
  else
    rc=$?
    if [[ $rc -eq 2 ]]; then
      skipped=$((skipped + 1))
    else
      exit $rc
    fi
  fi
done < "$CONF"

echo "---"
echo "已启动: ${started}  跳过(未配置 Key): ${skipped}"

if ((${#targets[@]} == 0)) && (( started > 0 )); then
  bash "${SCRIPT_DIR}/start_domestic_gateway.sh"
fi
