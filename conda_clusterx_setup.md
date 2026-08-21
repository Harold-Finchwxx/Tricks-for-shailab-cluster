# Conda + ClusterX 权威设置（wangxuanxu）

> **读我优先**：本文是本机 Conda / ClusterX 的单一事实来源（SSOT）。  
> Agent（Cursor / Codex / Qoder / Humanize）与用户本人提交任务前，先核对本节。

镜像文档副本：

- PVC：`/wangxuanxu/tricks-for-cluster/conda_clusterx_setup.md`（本文件）
- 团队盘：`/wam-model/wangxuanxu/ENVIRONMENT.md`（指向本文件）
- Agent 规则：`/wam-model/wangxuanxu/codex-home/AGENTS.md` 顶部「重要环境」一节

---

## 1. 一眼对照表（避免用错路径）

| 用途 | **唯一推荐路径** | 禁止 / 过时 |
|------|------------------|-------------|
| Conda 根 | `/wangxuanxu/miniconda3` | ~~`/root/miniconda3`~~（镜像残留，勿再当作默认） |
| ClusterX 专用 env | `/wangxuanxu/miniconda3/envs/clusterx-cli` | 不要装进项目 venv / 不要装多份 |
| 调用 ClusterX | `/wangxuanxu/bin/clusterx`（包装脚本） | 不要 `python -m clusterx`；不要依赖先 `conda activate` |
| ClusterX 真身 | `/wangxuanxu/miniconda3/envs/clusterx-cli/bin/clusterx` | — |
| 配置文件 | `/root/.config/clusterx.yaml`（当前会话 HOME=/root） | 副本：`/wangxuanxu/.config/clusterx.yaml` |
| 团队工作区 | `/wam-model/wangxuanxu`（挂载名可变） | 勿写死 `/mnt/share/...` |
| 调度 tmp | `/wam-model/wangxuanxu/clusterx-tmp/<project>/` | 不要把业务脚本放进 tmp |

版本（安装时）：

- Miniconda（PVC）：`conda 26.5.3`，base Python `3.14.x`
- `clusterx-cli`：Python `3.11.15`，`clusterx==2026.7.28`
- 旧 conda 备份：`/wangxuanxu/miniconda3.bak-conda412-20260813`

### 存放与镜像备份

- Conda 等大体积：**只在** `/wangxuanxu/miniconda3`（个人 PVC），不要指望打进系统配置镜像。  
- `/root/.bashrc`、`/root/.config/clusterx.yaml` 等小配置可留在系统侧；**一有改动必须提醒用户做镜像保存**，并写入 `agent-exec-report`。  
- 流程细则：`/wangxuanxu/tricks-for-cluster/agent_ops_and_reporting.md`

---

## 2. 默认 PATH 如何切换到 PVC conda

已写入：

- `/root/.bashrc`（当前开发机实际 HOME）
- `/wangxuanxu/.bashrc`

关键片段：

```bash
export WX_CONDA_ROOT="/wangxuanxu/miniconda3"
export PATH="/wangxuanxu/bin:${PATH}"
# 随后 conda initialize 使用 $WX_CONDA_ROOT，不再使用 $HOME/miniconda3
```

非交互 Agent 若未 source bashrc，至少保证：

```bash
export PATH="/wangxuanxu/bin:/wangxuanxu/miniconda3/bin:$PATH"
# 或
source /wangxuanxu/etc/wx_env.sh
```

验证：

```bash
which conda    # 期望: /wangxuanxu/bin/conda 或 /wangxuanxu/miniconda3/bin/conda
which clusterx # 期望: /wangxuanxu/bin/clusterx
clusterx --help
```

---

## 3. ClusterX 安装方式（专用小 env）

```bash
# 仅作记录；已完成安装，勿重复乱装到 /root
 /wangxuanxu/miniconda3/bin/conda create -y -p /wangxuanxu/miniconda3/envs/clusterx-cli python=3.11
 /wangxuanxu/miniconda3/envs/clusterx-cli/bin/pip install \
   /wangxuanxu/clusterx-2026.7.28-py3-none-any.whl \
   -i https://pkg.pjlab.org.cn/repository/pypi-tsinghua/simple
```

包装脚本 `/wangxuanxu/bin/clusterx` → 直接 `exec` 上述 env 内二进制，**无需 activate**。  
另有软链：`/root/.local/bin/clusterx` → `/wangxuanxu/bin/clusterx`。

官方说明（管理员）：<https://aicarrier.feishu.cn/docx/BJyHdJuszoDBhoxhqfncrTDInjc>

---

## 4. ClusterX 配置（`/root/.config/clusterx.yaml`）

副本：`/wangxuanxu/.config/clusterx.yaml`。查看：`clusterx config --show`。

### 当前约定

| 字段 | 值 |
|------|-----|
| queue | `queue-t-reserved-wammodel` |
| workspace | `ws-t-wammodel` |
| cluster | `cluster-t` / `PT` / `cn-pj-03` |
| image（默认） | `registry2.d.pjlab.org.cn/ccr-lepton-official-images/ngc-pytorch:25.06-cu12.9-py3.12-ubuntu24.04` |
| tmpdir | `/share/wangxuanxu/clusterx-tmp/_template`（项目任务改为 `.../clusterx-tmp/<project>/`） |
| mount | 个人 AFS → `/wangxuanxu`；团队 AFS → `/share` |

### 挂载（Job 与开发机路径对齐）

```text
PV_AFS:019fda05-f9e5-7b60-9dbc-e09fda024a89:/wangxuanxu,PV_AFS:019f8dc8-a09c-7e31-8d29-a28ab7d2a795:/share
```

- 个人卷 → `/wangxuanxu`；团队卷 → `/share`（UUID 均已校验为合法 8-4-4-4-12）。
- 开发机已做 `/share` → `/wam-model` 软链，使 `tmpdir` 与 Job 内 `/share/...` 一致。

### 可选镜像（按任务 `--image` 覆盖默认）

```text
registry2.d.pjlab.org.cn/ccr-lepton-official-images/ngc-pytorch:25.06-cu12.9-py3.12-ubuntu24.04
registry.pjlab.org.cn/ccr-lepton-official-images/ngc-pytorch:26.04-cu13.2-py3.12-ubuntu24.04-ss
registry.pjlab.org.cn/wxx_pre_setting:<tag>
# 例: registry.pjlab.org.cn/wxx_pre_setting:netproxy_humanize_with_fullaccess-20260810T120030
```

### 提交前检查

1. `clusterx config --show` 与本文一致。  
2. `tmpdir` 落在已挂载卷上，且开发机与 Job **同一绝对路径**。  
3. 正式项目不要用 `_template`，改用 `clusterx-tmp/<project>/`。

---

## 5. Agent 纪律（摘要）

1. 默认 conda = PVC `/wangxuanxu/miniconda3`，不是 `/root/miniconda3`。
2. 提交/查任务用 `clusterx`（PATH 上的包装脚本），不要在各项目 env 里再装一份。
3. 可复用脚本放团队工作区 `project/<name>/`；调度壳放 `clusterx-tmp/<name>/`。
4. 团队盘在 Job 内路径为 `/share/...`；开发机通过 `/share`→`/wam-model` 对齐。解析工作区仍可用 `WX_WORKSPACE_ROOT` / `resolve_root.sh`。
5. 配置以 `/root/.config/clusterx.yaml` 为准（PVC 副本：`/wangxuanxu/.config/clusterx.yaml`）。
