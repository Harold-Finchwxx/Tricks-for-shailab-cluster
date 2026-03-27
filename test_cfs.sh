#!/bin/bash

# 1) 基本环境与节点信息
hostname
uname -a

# 2) FUSE 工具是否存在（你当前最关键）
command -v fusermount3 || command -v fusermount || echo "NO_FUSERMOUNT"
ls -l /bin/fusermount* /usr/bin/fusermount* 2>/dev/null || true

# 3) CFS二进制与运行脚本是否存在
ls -l /mnt/petrelfs/wangxuanxu/cfs/bin/cfsctl
ls -l /mnt/hwfile/wangxuanxu/cfs/bin/chfsd
ls -l /mnt/hwfile/wangxuanxu/cfs/bin/../run/eb3d_t/default/srun.sh

# 4) 看 chfsd 的动态库依赖里有没有 not found（段错误常见根因）
ldd /mnt/hwfile/wangxuanxu/cfs/bin/chfsd | grep -E "not found|libmlx5|ibverbs|fuse" || true

# 5) RDMA 关键库文件是否在系统里
ldconfig -p 2>/dev/null | grep -E "ibverbs|mlx5|rdma" || true
ls -l /usr/lib64/libmlx5* /usr/lib*/libibverbs* 2>/dev/null || true

# 6) 检查内核是否启用 fuse
lsmod | grep -E "^fuse" || echo "FUSE_MODULE_NOT_LOADED"

# 7) 复核配置（确认 mount/backend 路径）
sed -n '1,120p' /mnt/petrelfs/wangxuanxu/cfsd.cfg