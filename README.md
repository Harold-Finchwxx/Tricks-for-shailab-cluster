# tricks-for-cluster

在 Slurm 集群（如 shailab / eb3d_t 等环境）下调试、训练与评测时积累的 **Shell 模版、诊断脚本与笔记**。路径与用户名默认使用 `${USER}`，复制到其他账号时请自行替换。

---

## 目录

| 类型 | 文件 | 说明 |
|------|------|------|
| 挂载模版 | [`data_mount_template_cfs_s3mount_none.sh`](data_mount_template_cfs_s3mount_none.sh) | CFS / s3mount / none 三模式数据挂载与清理 |
| CFS | [`cfs.sh`](cfs.sh)、[`cfs_test.sh`](cfs_test.sh)、[`test_cfs.sh`](test_cfs.sh) | cfsctl 最小示例、带读验证的测试、环境诊断 |
| s3mount | [`s3mount_compute_example.sh`](s3mount_compute_example.sh) | 计算节点上 s3mount 的 sbatch 示例与清理 |
| Slurm | [`slurm_only.sh`](slurm_only.sh) | 防止在登录节点执行的小片段 |
| 监控 | [`gpu_overview.sh`](gpu_overview.sh) | 按分区与 quota 类型汇总 GPU 占用 |
| 节点分析 | [`node_list.py`](node_list.py)、[`nodelist.py`](nodelist.py) | 解析 `squeue` 原始输出，按节点统计作业 |
| 编辑器 | [`cursor_install.sh`](cursor_install.sh) | 在集群侧安装 Cursor Server（远程开发） |
| 文档 | [`nccl_ib_p2p_multi_gpu_training.md`](nccl_ib_p2p_multi_gpu_training.md) | NCCL `IB_DISABLE` / `P2P_DISABLE` 说明 |
| 文档 | [`wandb_install_notes.md`](wandb_install_notes.md) | 集群上安装与登录 wandb 的注意事项 |

---

## 数据挂载模版：`cfs` / `s3mount` / `none`

核心脚本：**[`data_mount_template_cfs_s3mount_none.sh`](data_mount_template_cfs_s3mount_none.sh)**（从 VideoRAE `eval_stage1_rpipae_3stage_vit.sh` 抽象）。

### 三种模式含义

| 模式 | 含义 | 典型用途 |
|------|------|----------|
| **cfs** | 使用集群 `cfsctl` 将对象存储以 FUSE 挂到本地 NVMe（如 `/nvme/$USER/mnt/openvid`） | 与集群 CFS 服务配套的大规模数据 |
| **s3mount** | 使用用户态 `s3mount` + 配置文件（如 `s3mount.cfg`）挂载桶 | 与 VideoRAE `s3mount_for_training.sh` 联动的训练路径 |
| **none** | 不挂载，直接使用 `DATA_ROOT`（默认 `${REPO_ROOT}/src`） | 数据已在共享盘或仓库内 |

### 如何选择模式（环境变量）

- **`TRAIN_DATA_MOUNT`**（推荐显式设置）：`cfs` | `s3mount` | `none`，优先级最高。
- 若未设置 `TRAIN_DATA_MOUNT`，可用旧变量 **`CFS_USE`** 兼容映射：
  - `CFS_USE=1` → `cfs`
  - `CFS_USE=0` → `none`
  - 其他或未设 → 默认 **`s3mount`**

### CFS 常用变量

| 变量 | 作用 |
|------|------|
| `CFSCTL` | `cfsctl` 可执行路径，默认 `/mnt/petrelfs/${USER}/cfs/bin/cfsctl` |
| `CFS_MOUNT_PATH` | 挂载点，需与 `cfsd.cfg` 一致，如 `/nvme/${USER}/mnt/openvid` |
| `CFS_PARTITION` | Slurm 虚拟分区，常与 `SLURM_JOB_PARTITION` 一致 |
| `CFS_NNODES` | 参与 CFS 的节点数 |
| `CFS_MAIN_SERVER` | 多节点时 main server，一般为节点列表首节点 |

模版内含 **`start_cfs` / `stop_cfs`**，并在 **`EXIT` / `SIGTERM`** 时调用清理（避免异常退出占满缓存）。

### s3mount 常用说明

- 模版通过 **`S3MOUNT_LIB`** 指向业务仓库中的库脚本，默认 **`${REPO_ROOT}/src/s3mount_for_training.sh`**（VideoRAE）。
- 需自备 **`S3MOUNT_CFG`**、凭证、本地 NVMe 与 FUSE；详见该库内注释及本目录 [`s3mount_compute_example.sh`](s3mount_compute_example.sh)。

### 数据桥接（与训练脚本约定一致）

在 **cfs / s3mount** 下，脚本会创建 `LOCAL_DATA_ROOT=/nvme/${USER}/videorae_data_root`，并将 `openvid/videos` **符号链接**到挂载点下的视频目录；Python 侧使用 **`DATA_ROOT="${LOCAL_DATA_ROOT}"`**。

若 **`S3_PREFIX`** 为 `videos/` 等，可能将 **`TRAIN_OPENVID_VIDEOS_SUBDIR`** 设为 `.`，与训练脚本行为对齐。

### 使用方式

1. **直接执行**：仅打印环境变量，不跑训练（用于检查挂载是否就绪）。
2. **在业务脚本中 `source`**：在 `python torchrun ...` 之前 `source` 本模版，再使用 `$DATA_ROOT`。
3. **复制片段**：将模版内挂载与 `trap` 段落粘贴到自己的 `sbatch`/`srun` 包装脚本中。

---

## 各脚本说明

### `cfs.sh`

- **作用**：管理员文档风格的 **最小 cfs 流程**：`srun` 内 `cfsctl stop` → `start` → `ls` 挂载目录 → `stop`。
- **注意**：内含 `handle_sigterm`，但 **`MASTER_ADDR` 未赋值** 时 `trap` 中的 stop 可能无效；多节点时建议参考 `cfs_test.sh` 用 `scontrol show hostnames` 设置首节点。
- **适用**：快速验证分区、节点数与 `cfsctl` 是否可用。

### `cfs_test.sh`

- **作用**：在 **`cfs.sh` 基础上**增加 **挂载后读验证**：对 `/nvme/${USER}/mnt/openvid` 做 `stat`、`ls`，并用 `find` 抽样读文件（`head` + `wc`），最后再 `stop`。
- **参数**：`PARTITION`、`NNODES`、`CFSCTL` 在脚本开头修改；排队久时可给 `srun` 增加 `--quotatype=spot`（与集群策略一致）。
- **适用**：确认 CFS 不仅「挂上了」，还能 **读对象存储中的数据**。

### `test_cfs.sh`

- **作用**：**诊断当前节点**上的 FUSE、`fusermount`、`cfsctl`、`chfsd`、`cfsd.cfg`、RDMA 库等（路径示例中带固定用户名，使用前请改成你的路径或 `${USER}`）。
- **适用**：CFS 段错误、库缺失、挂载失败时对照排查。

### `s3mount_compute_example.sh`

- **作用**：集群文档风格的 **sbatch 示例**：在计算节点加载 `s3mount.cfg`、启动 `s3mount`、可 `sleep infinity` 保持挂载；`EXIT`/`SIGTERM` 时 `fusermount` 卸载。
- **变量**：`S3MOUNT_BIN`、`S3MOUNT_CFG`、`S3_LOG_DIR`、`AWS_SHARED_CREDENTIALS_FILE` 等可通过环境覆盖。
- **适用**：单独调试 s3mount，不与训练脚本耦合。

### `slurm_only.sh`

- **作用**：仅两行逻辑——**若无 `SLURM_JOB_ID` 则 `exit 0`**，避免在登录节点执行依赖计算节点本地盘/FUSE 的代码。
- **适用**：在其它脚本开头 `source slurm_only.sh`，或复制该判断。

### `gpu_overview.sh`

- **作用**：对分区 **`eb3d_t`** 分别统计 **`reserved`** 与 **`spot`** 队列中 **正在运行（R）** 作业占用的 GPU，按用户汇总并输出合计。
- **适用**：快速看当前分区 GPU 谁在用；若分区名变更需改脚本内 `get_gpu_usage` 参数。

### `node_list.py` 与 `nodelist.py`

- **作用**：读取 **`squeue` 保存的原始文本文件**（`--rawfile` 指定），解析节点列表、作业 ID、quota 类型（reserved/spot）、每节点 GPU/CPU 等，按 **纯 reserved / 混合 / 纯 spot** 分类打印。
- **参数**：`--fgpu` 时跳过「整节点 8 GPU」的节点（用于找非满卡节点等场景）。
- **注意**：两文件逻辑基本一致；结尾均会对 **`rawfile` 执行 `os.remove`**，若需保留原始文件请使用副本或改脚本。
- **适用**：比 `squeue` 默认输出更易做「按节点」的占用分析；需先自行将 `squeue` 输出重定向到文件。

### `cursor_install.sh`

- **作用**：下载指定 **commit / version** 的 Cursor CLI 与 `vscode-reh-linux-x64`，解压到 **`~/.cursor-server`**，供远程 SSH 开发使用。
- **注意**：脚本内 **版本号与 commit** 需与你的 Cursor 客户端匹配；路径与下载 URL 见文件头部注释。
- **适用**：在集群 home 下安装/更新 Cursor Server。

---

## 文档说明

### `nccl_ib_p2p_multi_gpu_training.md`

- **内容**：多卡 DDP 下 **`NCCL_IB_DISABLE`**、**`NCCL_P2P_DISABLE`** 的含义、设为 `0/1` 的影响、与 **`NCCL_SOCKET_IFNAME`** 等配合、与 VideoRAE 训练脚本的对齐方式。
- **适用**：多卡通信异常、利用率卡在 0、集体通信超时时的查阅。

### `wandb_install_notes.md`

- **内容**：集群上 **`pip install wandb`** 易触发源码构建失败的原因；推荐 **`WANDB_BUILD_SKIP_GPU_STATS`**、固定版本安装、**新版 86 位 API Key 需新版 wandb**；非交互作业用 **`WANDB_API_KEY`**。
- **适用**：安装/升级 wandb、登录与离线同步问题。

---

## 与 VideoRAE 的关系

本目录中的挂载逻辑与 **VideoRAE** 仓库内下列文件一致或互补：

- `VideoRAE/src/s3mount_for_training.sh` —— s3mount 训练用库  
- `VideoRAE/src/train_stage1_rpipae_3stage_vit.sh`、`eval_stage1_rpipae_3stage_vit.sh` —— 完整训练/评测入口  

将本仓库 **`data_mount_template_cfs_s3mount_none.sh`** 视为上述逻辑的 **可复用、带注释的抽离版** 即可。

---

## 许可证与贡献

个人工作区笔记与脚本，按需修改后使用；若提交到团队仓库，建议补充你们集群的分区名、路径规范与管理员文档链接。
