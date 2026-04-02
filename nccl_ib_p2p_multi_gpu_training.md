# 多卡训练 NCCL：`NCCL_IB_DISABLE` / `NCCL_P2P_DISABLE` 经验总结

## 背景说明

在 Slurm + PyTorch DDP（`torchrun`）多卡训练中，通信路径由 **NCCL** 负责。若未显式约束，NCCL 会在本机/集群上自动探测可用通道；在部分节点上，自动探测可能走次优路径，或与驱动、拓扑、容器环境不完全匹配，表现为：

- 多卡 GPU **利用率长期为 0 或交替为 0**（部分 rank 在等通信）；
- **`ALLREDUCE` / `broadcast` 等集体通信超时**、DDP watchdog 报错；
- 训练步速（steps/sec）明显低于同配置下的预期。

本仓库旧版 Wan-VAE Stage1 脚本 `train_stage1_wan_mysrun.sh` 中曾**显式**设置：

```bash
export NCCL_IB_DISABLE=0
export NCCL_P2P_DISABLE=0
```

RPiAE 三阶段脚本（`train_stage1_rpipae_3stage_{vit,wan}.sh`）后续已对齐该默认行为；本文档说明**含义、作用、适用场景与排查要点**，便于在其他作业或脚本中复用。

---

## 两个环境变量分别是什么

| 变量 | 典型取值 | 含义（通俗） |
|------|----------|--------------|
| `NCCL_IB_DISABLE` | `0` | **不禁用** InfiniBand / RoCE 等 RDMA 网络路径，允许 NCCL 使用高速网卡做机间（及某些拓扑下的）通信。 |
| `NCCL_IB_DISABLE` | `1` | **禁用** IB 路径，NCCL 更多依赖 socket/TCP 等，往往更慢、更易在高负载下抖动。 |
| `NCCL_P2P_DISABLE` | `0` | **不禁用** GPU 之间的 P2P（如 NVLink / 可用时的 PCIe P2P），单节点多卡常见的高效直连。 |
| `NCCL_P2P_DISABLE` | `1` | **禁用** P2P，可能退化为经 CPU/拷贝的较慢路径。 |

> 取值 `0` 表示「允许使用」；`1` 表示「关闭该通道」。是否与**本机实际硬件**匹配，仍由 NCCL 在运行时决定。

---

## 主要作用与能缓解的问题

1. **减少「自动选路」的不确定性**  
   显式设为 `0` 与旧 Wan 训练脚本一致，相当于在作业环境里明确：**优先允许** IB 与 P2P，避免在默认/继承环境里被误设为 `1` 或残留奇怪配置。

2. **缓解多卡不同步、长时间 0% 利用率**  
   当通信路径过慢或异常时，快的 rank 会在 `backward`/梯度同步处等待慢的 rank，nvidia-smi 上常看到**部分 GPU 利用率为 0**。改善通信路径后，这类现象常减轻（需与数据加载、FUSE 等因素区分）。

3. **降低集体通信超时概率**  
   在已有案例中，配合正确的网卡绑定（如 `NCCL_SOCKET_IFNAME` / `GLOO_SOCKET_IFNAME`）与稳定数据路径后，**`ALLREDUCE` 类超时**出现频率下降。

> **注意**：这两个变量**不能替代**正确的 `MASTER_ADDR`/`MASTER_PORT`、网卡选择、或修复「某 rank 在 Python 侧卡住」（如死锁、单 rank 异常慢的数据集访问）。它们是**通信栈侧的默认倾向**，不是万能开关。

---

## 推荐用法

### 1) 在提交作业前 export（与旧脚本一致）

```bash
export NCCL_IB_DISABLE=0
export NCCL_P2P_DISABLE=0
# 多机时通常还需（示例，以集群文档为准）：
# export NCCL_SOCKET_IFNAME=ib0
# export GLOO_SOCKET_IFNAME=ib0
```

### 2) 在训练 shell 脚本内默认导出（可被外部环境覆盖）

RPiAE 三阶段脚本中采用：

```bash
export NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-0}"
export NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-0}"
```

若某台机器或分区**明确不支持** IB 或 P2P，可在提交前覆盖：

```bash
export NCCL_IB_DISABLE=1   # 仅当管理员/文档要求或实测 IB 异常时
export NCCL_P2P_DISABLE=1   # 仅当 P2P 导致错误时（较少见）
```

---

## 与 RPiAE / VideoRAE 脚本的对应关系

| 位置 | 说明 |
|------|------|
| `VideoRAE/src/train_stage1_wan_mysrun.sh` | 历史脚本中写死 `NCCL_IB_DISABLE=0`、`NCCL_P2P_DISABLE=0`。 |
| `VideoRAE/src/train_stage1_rpipae_3stage_vit.sh` | 已用 `${VAR:-0}` 默认对齐，可在作业环境覆盖。 |
| `VideoRAE/src/train_stage1_rpipae_3stage_wan.sh` | 同上。 |

项目说明文档：`VideoRAE/RPiAE_MIGRATION_PROJECT.md` 中「环境变量」表亦补充了这两项的默认行为说明。

---

## 排查时如何确认是否生效

1. 在训练日志或作业脚本开头打印：

   ```bash
   echo "NCCL_IB_DISABLE=${NCCL_IB_DISABLE} NCCL_P2P_DISABLE=${NCCL_P2P_DISABLE}"
   ```

2. 需要更细通信日志时（仅调试用，日志会很大）：

   ```bash
   export NCCL_DEBUG=INFO
   ```

3. 结合 `gpu_logs` 里周期性 `nvidia-smi`：若**多卡长期同步有负载**而此前常出现「部分卡持续 0%」，可与改环境变量前后的对比作为旁证。

---

## 相关环境变量（多机/复杂网络时）

- **`NCCL_SOCKET_IFNAME` / `GLOO_SOCKET_IFNAME`**：指定本机用于 NCCL / Gloo（TCPStore）的网卡，需与 `MASTER_ADDR` 所在网段一致；多机作业常见必备项。
- **`NCCL_DEBUG`**：默认 `WARN` 即可；深度排障再开到 `INFO`。

详见 `VideoRAE/RPiAE_MIGRATION_PROJECT.md` 中多节点 Slurm 小节。

---

## 小结

- **`NCCL_IB_DISABLE=0`、`NCCL_P2P_DISABLE=0`**：在兼容的前提下，**允许** NCCL 使用 **RDMA 网卡**与 **GPU P2P**，通常有利于多卡吞吐与同步稳定性。  
- 当前 RPiAE 三阶段训练脚本已默认对齐；其他自定义作业可复制同一模式，并按集群要求用环境变量覆盖。  
- 若仍出现超时，应继续排查 **网络/ rendezvous、数据路径、DDP `find_unused_parameters`、单 rank 阻塞** 等，而不是仅依赖这两项。

---

*文档位置：`tricks-for-cluster/nccl_ib_p2p_multi_gpu_training.md` — 与集群侧脚本、VideoRAE 训练入口并列维护。*
