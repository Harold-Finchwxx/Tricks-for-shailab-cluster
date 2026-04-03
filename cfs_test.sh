#!/bin/bash

# 请将 partition、nnodes 替换为你自己的分区名和任务节点数，cfsctl 路径替换为你自己的路径
export PARTITION=eb3d_t
#export PARTITION=efm_t
export NNODES=2
export CFSCTL=/mnt/petrelfs/${USER}/cfs/bin/cfsctl
#export DEBUG=true

# 在 Slurm 作业内设置首节点，供 SIGTERM 清理使用（原模板里 MASTER_ADDR 未赋值）
if [ -n "${SLURM_NODELIST:-}" ]; then
  export MASTER_ADDR=$(scontrol show hostnames "$SLURM_NODELIST" | head -n1)
fi

handle_sigterm() {
  echo "Received SIGTERM signal. Cleaning up..."
  if [ -n "${MASTER_ADDR:-}" ]; then
    $CFSCTL -p "$PARTITION" -n "$NNODES" -X "$MASTER_ADDR" stop
  else
    echo "WARN: MASTER_ADDR 未设置，跳过 cfs stop"
  fi
  exit 0
}
trap 'handle_sigterm' SIGTERM

# 请根据需要补充你的 torchrun 命令（模拟测试可将 torchrun 换为 sleep）
# cfs 挂载和卸载命令分别添加在训练命令的前面和后面
# 建议 start 前先 stop：$CFSCTL -p $PARTITION -n $NNODES -X $MAIN_SERVER stop;

srun -p "$PARTITION" \
  --nodes="$NNODES" \
  --gres=gpu:1 \
  --ntasks="$NNODES" \
  --cpus-per-task=2 \
  bash -c 'export MAIN_SERVER=$(scontrol show hostnames "$SLURM_NODELIST" | head -n1); \
    $CFSCTL -p $PARTITION -n $NNODES -X $MAIN_SERVER stop; \
    $CFSCTL -p $PARTITION -n $NNODES -X $MAIN_SERVER -H 0 start; \
    sleep 5; \
    M="/nvme/${USER}/mnt/openvid"; \
    echo "========== CFS 挂载读验证 =========="; \
    if [ ! -d "$M" ]; then \
      echo "FAIL: 挂载目录不存在: $M"; \
    else \
      echo "OK: 目录存在: $M"; \
      stat "$M" || true; \
      echo "--- ls 顶层 (前 40 行) ---"; \
      ls -la "$M" | head -n 40; \
      echo "--- 顶层条目数 (含 . ..) ---"; \
      ls -1a "$M" 2>/dev/null | wc -l; \
      echo "--- 抽样读取文件 (maxdepth=3, 最多 5 个) ---"; \
      find "$M" -maxdepth 3 -type f 2>/dev/null | head -n 5 | while IFS= read -r f; do \
        echo "READ: $f"; \
        head -c 16384 "$f" 2>/dev/null | wc -c | awk "{print \"  bytes_read:\", \$1}"; \
      done; \
      echo "(若上无输出，可能桶内暂无小文件或列表较慢)"; \
    fi; \
    echo "========== 结束读验证，执行 stop =========="; \
    $CFSCTL -p $PARTITION -n $NNODES -X $MAIN_SERVER stop; \
  '
