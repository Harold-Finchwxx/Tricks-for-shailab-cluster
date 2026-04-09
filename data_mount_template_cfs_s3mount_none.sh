#!/bin/bash
# =============================================================================
# 数据挂载模版：TRAIN_DATA_MOUNT = cfs | s3mount | none
# -----------------------------------------------------------------------------
# 本文件从 VideoRAE「eval_stage1_rpipae_3stage_vit.sh」的挂载结构抽象而来，
# 用于在 Slurm 计算任务里统一处理：
#   - CFS：集群 cfsctl 把对象存储以 FUSE 形式挂到本地 NVMe 路径；
#   - s3mount：用户态 s3mount 把桶挂到本地路径（需 s3mount.cfg + 凭证）；
#   - none：不挂载，直接使用仓库内或共享盘上的 DATA_ROOT（如已同步的小数据集）。
#
# 使用方式（二选一）：
#   A) 复制本文件到业务仓库，改 REPO_ROOT / S3MOUNT_LIB，在「你的训练或评测命令」前 source
#        source /path/to/data_mount_template_cfs_s3mount_none.sh
#      （若仅想复用函数：可拆成单独 .sh 只保留函数与变量说明，由主脚本 source）
#   B) 把下面「--- 挂载逻辑开始 ---」到「--- 挂载逻辑结束 ---」整段粘贴进你的 bash 脚本。
#
# 环境变量速查（提交作业前可在 sbatch/srun 里 export）：
#   TRAIN_DATA_MOUNT   显式指定：cfs | s3mount | none（优先级最高）
#   CFS_USE            兼容老脚本：1 -> cfs，0 -> none，未设且 TRAIN_DATA_MOUNT 空 -> s3mount
#   CFS_* / S3MOUNT_*  见下文各节
# =============================================================================

# -----------------------------------------------------------------------------
# 可选：仅在计算节点执行本脚本（与 eval 脚本一致：登录节点直接退出）
# 若你的任务总在 srun 里跑，可取消下一行的注释。
# -----------------------------------------------------------------------------
# if [ -z "${SLURM_JOB_ID:-}" ]; then
#   exit 0
# fi

set -e

# -----------------------------------------------------------------------------
# 仓库根：请改成你的项目路径（用于默认 DATA_ROOT、以及 source s3mount 库）
# -----------------------------------------------------------------------------
: "${REPO_ROOT:=/mnt/petrelfs/${USER}/VideoRAE}"

# -----------------------------------------------------------------------------
# 1. 通用环境（按需保留；与 NCCL 训练脚本一致时可保留）
# -----------------------------------------------------------------------------
export NCCL_DEBUG="${NCCL_DEBUG:-WARN}"
export NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-0}"
export NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-0}"

# =============================================================================
# 2. CFS 相关变量（仅当 TRAIN_DATA_MOUNT=cfs 时使用）
# -----------------------------------------------------------------------------
# CFSCTL           cfsctl 可执行文件路径（每人 home 下一份）
# CFS_MOUNT_PATH   FUSE 挂载点（需与 cfsd.cfg 中该 bucket 的 CFS_MOUNT_PATH 一致）
# CFS_PARTITION    Slurm 虚拟分区名，须与 cfsctl -p 一致（常与 SLURM_JOB_PARTITION 相同）
# CFS_NNODES       参与 CFS 的节点数（多节点训练时与 SLURM_NNODES 一致）
# CFS_MAIN_SERVER  多节点时 cfs 的 main server，一般为节点列表第一个 hostname
# =============================================================================
export CFSCTL="${CFSCTL:-/mnt/petrelfs/${USER}/cfs/bin/cfsctl}"
export CFS_MOUNT_PATH="${CFS_MOUNT_PATH:-/nvme/${USER}/mnt/openvid}"
export CFS_PARTITION="${CFS_PARTITION:-${SLURM_JOB_PARTITION:-eb3d_t}}"
export CFS_NNODES="${CFS_NNODES:-${SLURM_NNODES:-1}}"
export CFS_MAIN_SERVER="${CFS_MAIN_SERVER:-$(scontrol show hostnames "${SLURM_JOB_NODELIST:-${SLURM_NODELIST}}" 2>/dev/null | head -n1)}"

# OpenVid 布局：视频通常在 bucket 下 videos/；若 CFS 整桶挂在 openvid，则子目录常为 videos
TRAIN_OPENVID_VIDEOS_SUBDIR="${TRAIN_OPENVID_VIDEOS_SUBDIR:-videos}"

# =============================================================================
# 3. 解析 TRAIN_DATA_MOUNT：显式优先，否则用 CFS_USE 映射，再默认 s3mount
# -----------------------------------------------------------------------------
# 设计目的：
#   - 新脚本统一用 TRAIN_DATA_MOUNT=cfs|s3mount|none；
#   - 旧脚本或环境只设了 CFS_USE=1/0 时仍能工作。
#
# 映射关系：
#   未设置 TRAIN_DATA_MOUNT 时：
#     CFS_USE=1  -> cfs
#     CFS_USE=0  -> none
#     其它/未设 -> s3mount（与当前 eval 默认一致）
# =============================================================================
CFS_USE="${CFS_USE-}"
if [ -z "${TRAIN_DATA_MOUNT:-}" ]; then
  case "${CFS_USE}" in
    1) TRAIN_DATA_MOUNT=cfs ;;
    0) TRAIN_DATA_MOUNT=none ;;
    *) TRAIN_DATA_MOUNT=s3mount ;;
  esac
fi
case "${TRAIN_DATA_MOUNT}" in
  none|cfs|s3mount) ;;
  *)
    echo "[FATAL] TRAIN_DATA_MOUNT 仅支持: none | cfs | s3mount，当前=${TRAIN_DATA_MOUNT}" >&2
    exit 1
    ;;
esac

# =============================================================================
# 4. CFS：启动 / 停止（start 前 stop 一次，避免上次异常退出残留）
# =============================================================================
start_cfs() {
  echo "[CFS] Starting mount on ${CFS_MAIN_SERVER} ..."
  mkdir -p "${CFS_MOUNT_PATH}"
  "${CFSCTL}" -p "${CFS_PARTITION}" -n "${CFS_NNODES}" -X "${CFS_MAIN_SERVER}" stop || true
  "${CFSCTL}" -p "${CFS_PARTITION}" -n "${CFS_NNODES}" -X "${CFS_MAIN_SERVER}" -H 0 start
  ls -1 "${CFS_MOUNT_PATH}" | sed "s|^|[CFS] mount entry: |" || true
}

stop_cfs() {
  echo "[CFS] Stopping mount on ${CFS_MAIN_SERVER} ..."
  "${CFSCTL}" -p "${CFS_PARTITION}" -n "${CFS_NNODES}" -X "${CFS_MAIN_SERVER}" stop || true
}

# =============================================================================
# 5. s3mount：由业务仓库提供的「库脚本」source（内含 start_s3mount_for_training 等）
# -----------------------------------------------------------------------------
# 默认指向 VideoRAE 内实现；其它项目请设置 S3MOUNT_LIB 或改 REPO_ROOT。
# 该库依赖：S3MOUNT_CFG（如 ~/s3mount.cfg）、本地 NVMe、FUSE、凭证等。
# =============================================================================
S3MOUNT_LIB="${S3MOUNT_LIB:-${REPO_ROOT}/src/s3mount_for_training.sh}"
if [ "${TRAIN_DATA_MOUNT}" = "s3mount" ]; then
  if [ ! -f "${S3MOUNT_LIB}" ]; then
    echo "[FATAL] TRAIN_DATA_MOUNT=s3mount 但未找到库脚本: ${S3MOUNT_LIB}" >&2
    echo "        请设置 S3MOUNT_LIB 指向你项目中的 s3mount_for_training.sh（或等价实现）。" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${S3MOUNT_LIB}"
fi

# =============================================================================
# 6. 数据桥接：把「挂载点下的视频目录」接到统一 DATA_ROOT（与训练脚本一致）
# -----------------------------------------------------------------------------
# 思路：
#   - cfs/s3mount 模式下，视频实际在 NVMe 上的 _MOUNT_VIDEOS_BASE/TRAIN_OPENVID_VIDEOS_SUBDIR；
#   - Python 侧往往约定 DATA_ROOT 下有 openvid/videos -> 真实数据；
#   - 因此创建 LOCAL_DATA_ROOT=/nvme/$USER/videorae_data_root，并用 ln -sfn 把
#     openvid/videos 指向上面的真实路径。
# none 模式：
#   - 不挂载，DATA_ROOT 默认为 REPO_ROOT/src（可被环境变量 DATA_ROOT 覆盖）。
# =============================================================================
if [ "${TRAIN_DATA_MOUNT}" = "cfs" ]; then
  start_cfs
  _MOUNT_VIDEOS_BASE="${CFS_MOUNT_PATH}"
elif [ "${TRAIN_DATA_MOUNT}" = "s3mount" ]; then
  start_s3mount_for_training
  _MOUNT_VIDEOS_BASE="${S3_MOUNT_PATH}"
  # 若 s3mount 使用 prefix=videos/，则「逻辑子目录」应为 . 而不是 videos（与训练脚本对齐）
  if [ "${TRAIN_OPENVID_VIDEOS_SUBDIR:-videos}" = "videos" ]; then
    case "${S3_PREFIX:-}" in
      videos/|*/videos/)
        TRAIN_OPENVID_VIDEOS_SUBDIR="."
        echo "[s3mount] S3_PREFIX=${S3_PREFIX} -> TRAIN_OPENVID_VIDEOS_SUBDIR=${TRAIN_OPENVID_VIDEOS_SUBDIR}"
        ;;
    esac
  fi
fi

if [ "${TRAIN_DATA_MOUNT}" = "cfs" ] || [ "${TRAIN_DATA_MOUNT}" = "s3mount" ]; then
  LOCAL_DATA_ROOT="/nvme/${USER}/videorae_data_root"
  mkdir -p "${LOCAL_DATA_ROOT}/openvid"
  _OPENVID_VID_SRC="${_MOUNT_VIDEOS_BASE}/${TRAIN_OPENVID_VIDEOS_SUBDIR}"
  ln -sfn "${_OPENVID_VID_SRC}" "${LOCAL_DATA_ROOT}/openvid/videos"
  DATA_ROOT="${LOCAL_DATA_ROOT}"
  if ! ls "${_OPENVID_VID_SRC}" >/dev/null 2>&1; then
    echo "[FATAL] OpenVid 视频路径不可读: ${_OPENVID_VID_SRC}"
    ls -la "${_MOUNT_VIDEOS_BASE}" 2>&1 | head -n 30 || true
    exit 1
  fi
  echo "[${TRAIN_DATA_MOUNT}] DATA_ROOT remapped to ${DATA_ROOT}; openvid/videos -> ${_OPENVID_VID_SRC}"
else
  DATA_ROOT="${DATA_ROOT:-${REPO_ROOT}/src}"
fi

# =============================================================================
# 7. 退出时清理：CFS stop / s3mount 卸载（避免占满缓存或残留挂载）
# -----------------------------------------------------------------------------
# SIGTERM：Slurm 超时或 scancel 时常发；务必在业务脚本里同样 trap，否则 cfs 可能无法清理。
# =============================================================================
cleanup_data_mount() {
  case "${TRAIN_DATA_MOUNT}" in
    cfs) stop_cfs ;;
    s3mount) stop_s3mount_for_training ;;
    none) ;;
  esac
}
trap cleanup_data_mount EXIT SIGTERM

# =============================================================================
# 8. 占位：以下为业务脚本应接上的训练/评测命令（本模版仅打印环境）
# -----------------------------------------------------------------------------
echo "========================================================"
echo "DATA_ROOT=              ${DATA_ROOT}"
echo "TRAIN_DATA_MOUNT=       ${TRAIN_DATA_MOUNT}"
echo "TRAIN_OPENVID_VIDEOS_SUBDIR=${TRAIN_OPENVID_VIDEOS_SUBDIR}"
echo "========================================================"
echo "在业务脚本中请使用: python ... --data-root \"\${DATA_ROOT}\""
echo "若直接执行本模版，到此处即结束（未跑训练/评测）。"
echo "========================================================"
