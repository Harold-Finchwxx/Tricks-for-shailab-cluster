#!/bin/bash

# 如果不是在 Slurm 任务环境里（即在登录节点本地），直接退出
if [ -z "$SLURM_JOB_ID" ]; then
  exit 0
fi
#用于防止srun时，任务在登录节点本地执行，而是直接在计算节点执行。