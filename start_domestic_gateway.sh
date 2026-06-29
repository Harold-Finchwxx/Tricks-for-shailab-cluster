#!/usr/bin/env bash
# 启动国产模型统一网关（8786），按 model 字段路由到各 provider 桥接

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY="${SCRIPT_DIR}/domestic_models_gateway.py"
BIND="${CODEX_GATEWAY_BIND:-127.0.0.1}"
PORT="${CODEX_GATEWAY_PORT:-8786}"
LOG_DIR="${CODEX_PROXY_LOG_DIR:-$HOME/.codex/proxy-logs}"
LOG_FILE="${LOG_DIR}/domestic-gateway.log"

mkdir -p "$LOG_DIR"

if pgrep -f "domestic_models_gateway.py.*--port ${PORT}" >/dev/null 2>&1; then
  pkill -f "domestic_models_gateway.py.*--port ${PORT}" || true
  sleep 1
fi

nohup python3 "$GATEWAY" --bind "$BIND" --port "$PORT" >>"$LOG_FILE" 2>&1 &

sleep 1
if curl -sf "http://${BIND}:${PORT}/health" >/dev/null 2>&1; then
  echo "OK  domestic-gateway -> http://${BIND}:${PORT}"
else
  echo "FAIL domestic-gateway health check; see ${LOG_FILE}" >&2
  tail -10 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi
