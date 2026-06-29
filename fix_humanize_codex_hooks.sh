#!/usr/bin/env bash
# 修复 Humanize hooks 与 Codex 0.142.x 的格式/feature 兼容问题
# 用法: bash ~/tricks-for-cluster/fix_humanize_codex_hooks.sh

set -euo pipefail

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
HOOKS_FILE="$CODEX_DIR/hooks.json"
CONFIG_FILE="$CODEX_DIR/config.toml"
PLUGIN_CACHE="$CODEX_DIR/plugins/cache/humanize-codex-qoder/humanize-codex-qoder"

fix_hooks_json() {
  if [[ ! -f "$HOOKS_FILE" ]]; then
    echo "跳过: 不存在 $HOOKS_FILE"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "错误: 需要 python3 处理 $HOOKS_FILE" >&2
    return 1
  fi
  python3 - "$HOOKS_FILE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(data, dict) or "hooks" not in data:
    raise SystemExit(f"invalid hooks file (missing 'hooks'): {path}")

changed = "description" in data
data = {"hooks": data["hooks"]}
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("OK  hooks.json" + (" (removed description)" if changed else " (already clean)"))
PY
}

fix_config_toml() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "跳过: 不存在 $CONFIG_FILE"
    return 0
  fi
  if grep -q '^codex_hooks\s*=' "$CONFIG_FILE" 2>/dev/null; then
    sed -i 's/^codex_hooks\s*=.*/hooks = true/' "$CONFIG_FILE"
    echo "OK  config.toml (codex_hooks -> hooks)"
  elif grep -q '^hooks\s*=\s*true' "$CONFIG_FILE" 2>/dev/null; then
    echo "OK  config.toml (hooks already enabled)"
  else
    printf '\n[features]\nhooks = true\n' >>"$CONFIG_FILE"
    echo "OK  config.toml (appended [features] hooks = true)"
  fi
}

disable_plugin_claude_hooks() {
  local found=0
  shopt -s nullglob
  for f in "$PLUGIN_CACHE"/*/hooks/hooks.json; do
    found=1
    mv "$f" "${f}.bak"
    echo "OK  renamed $(dirname "$f")/hooks.json -> hooks.json.bak"
  done
  shopt -u nullglob
  if (( found == 0 )); then
    echo "跳过: 未找到插件缓存 hooks/hooks.json（可能已修复或未安装插件）"
  fi
}

echo "Codex dir: $CODEX_DIR"
fix_hooks_json
fix_config_toml
disable_plugin_claude_hooks
echo "---"
echo "完成。请重新启动 codex / codex-cn。"
