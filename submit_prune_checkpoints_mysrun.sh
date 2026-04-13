#!/bin/bash
# 在计算节点上执行检查点扫描/删除（调用 prune_checkpoints.py）。
# 本脚本内不包含 mysrun；请在登录节点用 mysrun 提交本脚本，例如:
#
#   bash -l -c 'mysrun -g 0 -c 2 -j prune-ckpt -a bash /mnt/petrelfs/wangxuanxu/tricks-for-cluster/submit_prune_checkpoints_mysrun.sh'
#
# 同步等待输出（不加 -a）:
#   bash -l -c 'mysrun -g 0 -c 2 -j prune-ckpt bash /mnt/petrelfs/wangxuanxu/tricks-for-cluster/submit_prune_checkpoints_mysrun.sh'
#
# 若队列不允许 gpu:0，把 -g 0 改成 -g 1。

# 如果不是在 Slurm 任务环境里（即在登录节点本地），直接退出
if [ -z "$SLURM_JOB_ID" ]; then
  exit 0
fi
#用于防止srun时，任务在登录节点本地执行，而是直接在计算节点执行。

set -euo pipefail

# ---------- 配置区 ----------
PRUNE_SCRIPT="/mnt/petrelfs/wangxuanxu/tricks-for-cluster/prune_checkpoints.py"
PYTHON="${PYTHON:-python3}"

CKPT_DIRS=(
  "/mnt/inspurfs/eb3d_t/wangxuanxu/VideoRAE/results/Stage2-WanVAE-debug/openvid_3w2_from_0040000_temporal_16_4_16/006-WanVideoRAE_DDTAdapter-Linear-velocity-none-bf16-acc1/checkpoints"
  "/mnt/inspurfs/eb3d_t/wangxuanxu/VideoRAE/results/RPiAE-MAEv2-3stage-ViT-Offline-Pivot/stageI/005-VideoRAERPiAE-bf16/checkpoints"
  "/mnt/inspurfs/eb3d_t/wangxuanxu/VideoRAE/results/Stage2-WanVAE-debug/openvid_3w2_from_0120000/temporal_16_8_16_in_s2/004-WanVideoRAE_DDTAdapter-Linear-velocity-none-bf16-acc1/checkpoints"
  # "/path/to/checkpoint_dir_2"
)

MAX_KEEP=4

# 是否递归子目录：1=传递 Python 的 -r（扫所有层级的 .pt/.ckpt）；0=只扫每个 DIR 下的一层文件
RECURSIVE="${RECURSIVE:-1}"

# 非空则传 --interval SEC；留空则只跑一轮
INTERVAL_SEC="${INTERVAL_SEC:-300}"

EXTRA_PY_ARGS=()
# ---------- 配置区结束 ----------

if [[ ! -f "$PRUNE_SCRIPT" ]]; then
  echo "错误: 找不到脚本: $PRUNE_SCRIPT" >&2
  exit 1
fi

if [[ ${#CKPT_DIRS[@]} -eq 0 ]]; then
  echo "错误: 请在脚本中填写 CKPT_DIRS（至少一个目录）。" >&2
  exit 1
fi

for d in "${CKPT_DIRS[@]}"; do
  if [[ ! -d "$d" ]]; then
    echo "错误: 目录不存在: $d" >&2
    exit 1
  fi
done

INTERVAL_ARGS=()
if [[ -n "$INTERVAL_SEC" ]]; then
  INTERVAL_ARGS=(--interval "$INTERVAL_SEC")
fi

# set -u 下，bash 4.2 等对「空数组」的 "${arr[@]}" 会报 unbound variable，需非空再追加
cmd=(
  "$PYTHON" "$PRUNE_SCRIPT"
  "${CKPT_DIRS[@]}"
  --max "$MAX_KEEP"
)
((${#INTERVAL_ARGS[@]})) && cmd+=("${INTERVAL_ARGS[@]}")
[[ "$RECURSIVE" == "1" ]] && cmd+=(-r)
((${#EXTRA_PY_ARGS[@]})) && cmd+=("${EXTRA_PY_ARGS[@]}")
exec "${cmd[@]}"
