#!/bin/bash

# 请将partition， nnodes替换为你自己的分区名和任务节点数，cfsctl路径替换为你自己的路径
export PARTITION=eb3d_t
export NNODES=1
export CFSCTL=/mnt/petrelfs/${USER}/cfs/bin/cfsctl

# 有些研究员，会因为某些原因（不等任务正常结束）直接关闭任务，这会导致cfs没有机会执行清理操作
# 时间久了，会导致缓存盘空间被占满，因此强烈建议各研究员在自己的训练脚本中捕获SIGTERM信号，
# 并且将cfs卸载命令包裹到信号处理函数中，下面是一个示例：
# 定义用于处理sigterm信号的函数，里面包含cfs的卸载命令
handle_sigterm() {
    echo "Received SIGTERM signal. Cleaning up..."
    $CFSCTL -p $PARTITION -n $NNODES -X $MASTER_ADDR stop
    exit 0
}
# 为sigterm信号安装处理函数
trap 'handle_sigterm' SIGTERM

# 请根据需要补充你的torchrun命令（如果你只想进行模拟测试，那么就将本脚本保存到shell文件中，如：cfs.sh
# torchrun替换为sleep吧，比如：sleep 600，然后执行sh cfs.sh，之后可以通过srun命令远程访问指定节点上的挂载点），
# cfs挂载和卸载命令分别添加在torchrun命令的前面和后面（直接copy下方红色字体的挂载和卸载命令接即可）
# TODO:: 预加载，内测中，暂勿使用
# preload命令用于缓存预热：即将桶中的数据预加载到cfs缓存中，默认是异步加载，如果需要同步加载，请将
# 命令中的-a选项去掉；如果不需要预热，请删除该命令

# 在进行模拟测试的实践中，我们发现很多同学喜欢直接ctrl-c杀掉脚本，这会导致cfs无法完成清理，影响下次的运行，
# 那么建议你在下述命令的$CFSCTL ... start命令前，也添加一条stop，如：$CFSCTL -p $PARTITION -n $NNODES -X $MAIN_SERVER stop;
srun -p $PARTITION \
    --nodes=$NNODES \
    bash -c 'export MAIN_SERVER=$(scontrol show hostname $SLURM_NODELIST | head -n1);    \
        $CFSCTL -p $PARTITION -n $NNODES -X $MAIN_SERVER -H 0 start;   \
        ls /nvme/$USER/mnt;                                             \
        $CFSCTL -p $PARTITION -n $NNODES -X $MAIN_SERVER stop;    \
    '
    
#
# 如果脚本执行日志中显示如下的错误，表明节点上没有nvme盘，可以考虑添加srun选项--exclude=hosts
# 排除相应的节点， 示例：--exclude=SH-IDC1-10-140-0-70
# mkdir: cannot create directory ‘/nvme’: Permission denied
# [SH-IDC1-10-140-0-70]: srun.sh: /nvme/${USER}/mnt1 no such directory
#
# 如果执行脚本出现：srun: error: Unable to allocate resources: Requested node configuration is not available
# 请增加srun选项--ntasks=$NNODES，如：srun -p $PARTITION --nodes=$NNODES --ntasks=$NNODES ...
#