#!/bin/bash
# =============================================================================
# 集群管理部门：s3mount 在计算节点上的用法（通过 sbatch/srun 提交，勿在登录节点直接挂载）
# - 二进制：优先 /mnt/petrelfs/share_data/s3mount；若不存在则使用 /mnt/petrelfs/${USER}/s3mount（也可 export S3MOUNT_BIN=路径）
# - 凭证：在 /mnt/petrelfs/{AD}/.aws/credentials 配置 AK/SK（AD 即用户名，与下文 ${USER} 一致）
# - 每个桶使用不同的 mountpoint / cachepoint，避免冲突；缓存目录须为空或可被快速清空（见下方说明）
#
# 提交示例（将 {hostname} 换为指定节点名，不需要固定节点时可去掉 -w）：
#   sbatch -p eb3d_t -w {hostname} tricks-for-cluster/s3mount_compute_example.sh
#
# 结束挂载（与文档一致：按作业名取消任务）：
#   scancel -p eb3d_t -w {hostname} --job-name=mys3mountjob
#   或：scancel <JobID>
# =============================================================================
#SBATCH -J mys3mountjob
#SBATCH -p eb3d_t
#SBATCH -N 1
## 需要固定到某台计算节点时取消下一行注释并填写节点名：
##SBATCH -w {hostname}

# 如果不是在 Slurm 任务环境里（即在登录节点本地），直接退出
if [ -z "$SLURM_JOB_ID" ]; then
  exit 0
fi
#用于防止srun时，任务在登录节点本地执行，而是直接在计算节点执行。

set -eo pipefail

# 与 pipefail 同时开 -u 时需注意空数组展开；本脚本对可选参数用条件追加，避免 unbound
set -u

# ---------- 可调参数（也可用环境变量覆盖）----------
export PARTITION="${PARTITION:-eb3d_t}"
# 集群文档路径在部分环境尚未挂载时，自动回退到用户 petrelfs 下副本
if [ -n "${S3MOUNT_BIN:-}" ] && [ -x "$S3MOUNT_BIN" ]; then
  :
elif [ -x /mnt/petrelfs/share_data/s3mount ]; then
  export S3MOUNT_BIN=/mnt/petrelfs/share_data/s3mount
elif [ -x "/mnt/petrelfs/${USER}/s3mount" ]; then
  export S3MOUNT_BIN="/mnt/petrelfs/${USER}/s3mount"
else
  export S3MOUNT_BIN=/mnt/petrelfs/share_data/s3mount
fi
export S3MOUNT_CFG="${S3MOUNT_CFG:-/mnt/petrelfs/${USER}/s3mount.cfg}"
# 日志目录：建议共享存储，便于拷日志给管理员；占用 KB～MB 级
export S3_LOG_DIR="${S3_LOG_DIR:-/mnt/petrelfs/${USER}/s3mount-logs}"
# 若凭证只放在文件里且非默认路径，可指定：
export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-/mnt/petrelfs/${USER}/.aws/credentials}"

# 快速联调：设置后不再 sleep infinity，而是睡眠若干秒后退出（仍会走 cleanup）
export S3MOUNT_QUICK_TEST_SEC=60

# ---------- 工具函数 ----------
cleanup_s3mount() {
  local mp="${S3_MOUNT_PATH:-}"
  [ -z "$mp" ] && return 0
  if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$mp" 2>/dev/null; then
    echo "[cleanup] fusermount -u ${mp}"
    fusermount -u "$mp" 2>/dev/null || umount "$mp" 2>/dev/null || true
  elif grep -q " ${mp} fuse" /proc/mounts 2>/dev/null; then
    fusermount -u "$mp" 2>/dev/null || true
  fi
}

# scancel 等会发 SIGTERM；bash 退出时会执行 EXIT，此处统一卸载
trap 'cleanup_s3mount' EXIT

load_s3mount_cfg() {
  local tmp
  tmp="$(mktemp)"
  sed '/^\[[^]]*\]$/s/^/# /' "$S3MOUNT_CFG" > "$tmp"
  set -a
  # shellcheck source=/dev/null
  source "$tmp"
  set +a
  rm -f "$tmp"
}

preflight() {
  if [ ! -x "$S3MOUNT_BIN" ]; then
    echo "ERROR: s3mount 不可执行: $S3MOUNT_BIN" >&2
    echo "      请确认 /mnt/petrelfs/share_data/s3mount 已部署，或自行下载后放到 /mnt/petrelfs/\${USER}/s3mount，或 export S3MOUNT_BIN=绝对路径" >&2
    exit 1
  fi
  if [ ! -f "$S3MOUNT_CFG" ]; then
    echo "ERROR: 未找到配置文件: $S3MOUNT_CFG" >&2
    exit 1
  fi
  if [ ! -e /dev/fuse ]; then
    echo "ERROR: /dev/fuse 不存在，当前环境可能不支持 FUSE" >&2
    exit 1
  fi
  if ! command -v fusermount >/dev/null 2>&1 && ! command -v fusermount3 >/dev/null 2>&1; then
    echo "ERROR: 未找到 fusermount/fusermount3" >&2
    exit 1
  fi
  if [ ! -f "$AWS_SHARED_CREDENTIALS_FILE" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "WARN: 未检测到 ${AWS_SHARED_CREDENTIALS_FILE} 且未设置 AWS_ACCESS_KEY_ID；请先配置凭证（见脚本头注释）。" >&2
  fi
}

# 文档：请确保缓存目录为空；非空时 s3mount 会尝试清空，数据量大可能超时失败
ensure_empty_or_warn_cache() {
  local cdir="$1"
  if [ -d "$cdir" ] && [ -n "$(ls -A "$cdir" 2>/dev/null)" ]; then
    echo "WARN: 缓存目录非空: $cdir — 可能导致挂载慢或失败；请换 S3_CACHE_PATH 或清空后再试。" >&2
  fi
}

run_mount_admin_style() {
  local -a args
  local mp cp
  mp="${S3_MOUNT_PATH:?请在 s3mount.cfg 中设置 S3_MOUNT_PATH}"
  cp="${S3_CACHE_PATH:?请在 s3mount.cfg 中设置 S3_CACHE_PATH}"

  mkdir -p "$S3_LOG_DIR"
  mkdir -p "$mp"
  mkdir -p "$cp"
  ensure_empty_or_warn_cache "$cp"

  # --endpoint-url 为域名时加 --force-path-style（阿里云 OSS 等例外见文档）
  args=("$S3MOUNT_BIN")
  args+=(--cache "$cp")
  # 管理部门示例使用 --allow-delete；若仅只读数据集可在 s3mount.cfg 设 S3_MOUNT_READ_ONLY=1 以改为 --read-only
  if [ "${S3_MOUNT_READ_ONLY:-0}" = "1" ]; then
    args+=(--read-only)
  else
    args+=(--allow-delete)
  fi
  args+=(--endpoint-url "${AWS_ENDPOINT_URL:?请在 s3mount.cfg 中设置 AWS_ENDPOINT_URL}")
  args+=(--log-directory "$S3_LOG_DIR")

  [ "${S3_FORCE_PATH_STYLE:-true}" = "true" ] && args+=(--force-path-style)
  [ -n "${AWS_DEFAULT_REGION:-}" ] && args+=(--region "$AWS_DEFAULT_REGION")
  [ -n "${S3_PREFIX:-}" ] && args+=(--prefix "$S3_PREFIX")

  # 匿名访问
  [ "${S3_NO_SIGN_REQUEST:-0}" = "1" ] && args+=(--no-sign-request)
  # 阿里云 OSS 等：与文档一致时可打开
  [ "${S3_USE_LISTOBJECT_V2:-0}" = "1" ] && args+=(--use-listobject-v2)

  args+=("${S3_BUCKET:?请在 s3mount.cfg 中设置 S3_BUCKET}" "$mp")

  echo "[mount] ${args[*]}"
  if [ "${S3MOUNT_UNSET_PROXY:-1}" = "1" ]; then
    ( unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; exec "${args[@]}" )
  else
    "${args[@]}"
  fi
}

# ---------- 主流程（对齐文档：cd /nvme/{AD}，等待路径就绪，再挂载）----------
if [ -z "${SLURM_JOB_ID:-}" ]; then
  echo "WARN: 未检测到 SLURM_JOB_ID。请通过 sbatch/srun 在计算节点上运行本脚本。" >&2
fi

preflight
load_s3mount_cfg

: "${S3_BUCKET:?}"
: "${AWS_ENDPOINT_URL:?}"
: "${S3_MOUNT_PATH:?}"
: "${S3_CACHE_PATH:?}"

cd "/nvme/${USER}" || {
  echo "ERROR: 无法 cd 到 /nvme/${USER}（当前节点是否无本地盘？）" >&2
  exit 1
}

sleep 5

cleanup_s3mount

run_mount_admin_style

if ! ls "${S3_MOUNT_PATH}" >/dev/null 2>&1; then
  echo "ERROR: 挂载点不可访问: ${S3_MOUNT_PATH}" >&2
  exit 1
fi
echo "[ok] 挂载就绪: ${S3_MOUNT_PATH}"

# 文档：sleep infinity 保持 s3mount 存活；结束用 scancel 作业名
if [ -n "${S3MOUNT_QUICK_TEST_SEC:-}" ]; then
  echo "[test] sleep ${S3MOUNT_QUICK_TEST_SEC}s 后退出并卸载"
  sleep "${S3MOUNT_QUICK_TEST_SEC}"
else
  sleep infinity
fi
