#!/usr/bin/env bash
# 启动单个 Chat Completions -> Responses 桥接（供 Codex custom provider 使用）
# 用法: start_codex_responses_proxy.sh <provider_id> <port> <upstream_base_url> <api_key_env>

set -euo pipefail

PROVIDER_ID="${1:?provider_id required}"
PORT="${2:?port required}"
UPSTREAM="${3:?upstream_base_url required}"
API_KEY_ENV="${4:?api_key_env required}"

BIND="${CODEX_PROXY_BIND:-127.0.0.1}"
LOG_DIR="${CODEX_PROXY_LOG_DIR:-$HOME/.codex/proxy-logs}"
LOG_FILE="${LOG_DIR}/${PROVIDER_ID}.log"

_read_bashrc_var() {
  local name="$1"
  grep -E "^${name}=" "$HOME/.bashrc" 2>/dev/null | head -1 | sed -E "s/^${name}=//; s/^\"//; s/\"$//"
}

PROXY_URL="${PROXY_URL:-$(_read_bashrc_var PROXY_URL)}"
NO_PROXY_LIST="${NO_PROXY_LIST:-$(_read_bashrc_var NO_PROXY_LIST)}"
NO_PROXY_LIST="${NO_PROXY_LIST:-localhost,127.0.0.1}"

if [[ -f "$HOME/.domestic_models_env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.domestic_models_env"
fi
if [[ -f "$HOME/.deepseek_env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.deepseek_env"
fi

if [[ -z "${PROXY_URL:-}" ]]; then
  echo "错误: 未找到 PROXY_URL（~/.bashrc 中的 proxy_on）。" >&2
  exit 1
fi

API_KEY_VALUE="${!API_KEY_ENV-}"
if [[ -z "$API_KEY_VALUE" ]]; then
  echo "跳过 ${PROVIDER_ID}: 未设置 ${API_KEY_ENV}" >&2
  exit 2
fi
if [[ "$API_KEY_VALUE" == *"your-"* ]] || [[ "$API_KEY_VALUE" == *"-your-"* ]]; then
  echo "跳过 ${PROVIDER_ID}: ${API_KEY_ENV} 仍是占位符" >&2
  exit 2
fi

export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$LOG_DIR"

if pgrep -f "deepseek-responses-proxy.*--port ${PORT}" >/dev/null 2>&1; then
  pkill -f "deepseek-responses-proxy.*--port ${PORT}" || true
  sleep 1
fi

if ! command -v deepseek-responses-proxy >/dev/null 2>&1; then
  echo "错误: 未找到 deepseek-responses-proxy，见 codex_domestic_models_setup.md" >&2
  exit 1
fi

nohup env \
  "${API_KEY_ENV}=${API_KEY_VALUE}" \
  http_proxy="$PROXY_URL" \
  https_proxy="$PROXY_URL" \
  HTTP_PROXY="$PROXY_URL" \
  HTTPS_PROXY="$PROXY_URL" \
  no_proxy="$NO_PROXY_LIST" \
  NO_PROXY="$NO_PROXY_LIST" \
  deepseek-responses-proxy \
  --bind "$BIND" \
  --port "$PORT" \
  --chat-base-url "$UPSTREAM" \
  --api-key-env "$API_KEY_ENV" \
  >>"$LOG_FILE" 2>&1 &

sleep 1
if curl -sf "http://${BIND}:${PORT}/health" >/dev/null 2>&1; then
  echo "OK  ${PROVIDER_ID} -> http://${BIND}:${PORT}  upstream=${UPSTREAM}"
else
  echo "FAIL ${PROVIDER_ID} health check; see ${LOG_FILE}" >&2
  tail -10 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi
