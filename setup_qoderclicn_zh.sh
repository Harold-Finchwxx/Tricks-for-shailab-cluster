#!/usr/bin/env bash
# 为 qoderclicn 注入默认「简体中文回复」系统提示（wrapper）
# 安装: bash ~/tricks-for-cluster/setup_qoderclicn_zh.sh

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
REAL_LINK="${BIN_DIR}/.qoderclicn-real"
WRAPPER="${BIN_DIR}/qoderclicn"
HUMANIZE_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/humanize/config.json"

DEFAULT_ZH_PROMPT='始终用简体中文回复用户，除非用户明确要求使用其他语言。代码、标识符、路径、commit message 等技术内容保持英文。'

resolve_current_real() {
  if [[ -L "$WRAPPER" ]]; then
    readlink -f "$WRAPPER"
    return 0
  fi
  if [[ -x "$REAL_LINK" || -L "$REAL_LINK" ]]; then
    readlink -f "$REAL_LINK"
    return 0
  fi
  command -v qoderclicn 2>/dev/null && readlink -f "$(command -v qoderclicn)" || true
}

REAL_BIN="$(resolve_current_real)"
if [[ -z "$REAL_BIN" || ! -e "$REAL_BIN" ]]; then
  echo "错误: 未找到 qoderclicn 二进制，请先安装 qoderclicn" >&2
  exit 1
fi

# 若 REAL_BIN 已是本 wrapper 脚本（曾被误写入 symlink 目标），拒绝继续
if head -1 "$REAL_BIN" 2>/dev/null | grep -q '^#!/usr/bin/env bash'; then
  if grep -q 'qoderclicn wrapper' "$REAL_BIN" 2>/dev/null; then
    echo "错误: qoderclicn 二进制已被破坏，请先重装:" >&2
    echo "  curl -fsSL https://qoder.com.cn/install | bash -s -- --force" >&2
    exit 1
  fi
fi

mkdir -p "$BIN_DIR"
ln -sf "$REAL_BIN" "$REAL_LINK"

# 必须先删除 symlink，再写入 wrapper 文件；否则 cat> 会覆盖真实二进制
rm -f "$WRAPPER"

cat >"$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
# qoderclicn wrapper: 默认追加简体中文系统提示（由 tricks-for-cluster/setup_qoderclicn_zh.sh 安装）

# Pin HOME for root so auth persists under /root/.qoder-cn
if [[ "$(id -u)" -eq 0 ]]; then
  export HOME=/root
fi

REAL="${QODERCLICN_REAL_BIN:-$HOME/.local/bin/.qoderclicn-real}"
ZH_PROMPT="${QODERCLICN_APPEND_SYSTEM_PROMPT:-始终用简体中文回复用户，除非用户明确要求使用其他语言。代码、标识符、路径、commit message 等技术内容保持英文。}"

if [[ ! -e "$REAL" ]]; then
  echo "qoderclicn wrapper: missing real binary at $REAL" >&2
  exit 127
fi

# T 集群需 Authentik 出站代理才能访问 gateway.qoder.com.cn
_read_bashrc_var() {
  local name="$1"
  grep -E "^${name}=" "$HOME/.bashrc" 2>/dev/null | head -1 | sed -E "s/^${name}=//; s/^\"//; s/\"$//"
}
if [[ -z "${http_proxy:-}" && -z "${HTTP_PROXY:-}" ]]; then
  _PROXY_URL="${PROXY_URL:-$(_read_bashrc_var PROXY_URL)}"
  if [[ -n "$_PROXY_URL" ]]; then
    export http_proxy="$_PROXY_URL" https_proxy="$_PROXY_URL"
    export HTTP_PROXY="$_PROXY_URL" HTTPS_PROXY="$_PROXY_URL"
  fi
fi
unset -f _read_bashrc_var 2>/dev/null || true

# 调用方已显式指定 system prompt 时不重复注入
for arg in "$@"; do
  case "$arg" in
    --append-system-prompt|--system-prompt)
      exec "$REAL" "$@"
      ;;
  esac
done

exec "$REAL" --append-system-prompt "$ZH_PROMPT" "$@"
WRAPPER_EOF

chmod +x "$WRAPPER"

# Humanize 配置（ask-qoder 若未来读取该键可复用；文档用途）
mkdir -p "$(dirname "$HUMANIZE_CFG")"
python3 - "$HUMANIZE_CFG" "$DEFAULT_ZH_PROMPT" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
prompt = sys.argv[2]
data = {}
if path.is_file():
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"invalid json object: {path}")
data["qoder_append_system"] = prompt
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"OK  {path}")
PY

echo "OK  wrapper -> $WRAPPER"
echo "OK  real bin -> $REAL_BIN (via $REAL_LINK)"
echo "测试: qoderclicn --help | head -1"
"$WRAPPER" --help 2>&1 | head -1
