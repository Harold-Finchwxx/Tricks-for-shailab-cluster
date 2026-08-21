#!/usr/bin/env bash
# Write a Beijing-time agent-exec-report for one slot (1200|1700|2100).
# Deletion-safe: never requires prior reports; mkdir -p + atomic mv.
set -euo pipefail

REPORT_ROOT="${WX_AGENT_EXEC_REPORT_ROOT:-/wangxuanxu/agent-exec-report}"
TZ_SH="Asia/Shanghai"

slot="${1:-}"
if [[ -z "$slot" ]]; then
  # Map current Beijing time to the next/current reporting slot of the day.
  # Before 12:00 -> 1200; [12,17) -> 1700; [17,21) -> 2100; else -> 1200 next day handled by date.
  hhmm="$(TZ="$TZ_SH" date +%H%M)"
  if (( 10#$hhmm < 1200 )); then
    slot=1200
  elif (( 10#$hhmm < 1700 )); then
    slot=1700
  elif (( 10#$hhmm < 2100 )); then
    slot=2100
  else
    slot=2100
  fi
fi

case "$slot" in
  1200|1700|2100) ;;
  *)
    echo "usage: $0 [1200|1700|2100] < report_body.md" >&2
    exit 2
    ;;
esac

day="$(TZ="$TZ_SH" date +%F)"
dir="$REPORT_ROOT/$day"
mkdir -p "$dir"

period_label=""
case "$slot" in
  1200) period_label="1200（北京时间，覆盖上一日 21:00 → 当日 12:00）" ;;
  1700) period_label="1700（北京时间，覆盖当日 12:00 → 17:00）" ;;
  2100) period_label="2100（北京时间，覆盖当日 17:00 → 21:00）" ;;
esac

generated="$(TZ="$TZ_SH" date '+%F %T %Z')"
body="$(cat)"
tmp="$(mktemp "$dir/.${slot}.XXXXXX")"
{
  printf '%s\n' "# Agent Exec Report — ${day} / ${slot}"
  printf '%s\n' ""
  printf '%s\n' "- 时段：${period_label}"
  printf '%s\n' "- 生成时间（北京）：${generated}"
  printf '%s\n' "- 说明：本文件可随时删除；下次生成不依赖本文件是否存在。"
  printf '%s\n' ""
  printf '%s\n' "$body"
  printf '%s\n' ""
} >"$tmp"
mv -f "$tmp" "$dir/${slot}.md"
printf '%s\n' "$dir/${slot}.md"
