# Agent 运维纪律与执行报告（wangxuanxu）

> **读我优先（与集群框架相关的流程变更）**  
> 个人目录 SSOT：`/wangxuanxu/tricks-for-cluster/agent_ops_and_reporting.md`（本文件）  
> 同步入口：`/wam-model/wangxuanxu/codex-home/AGENTS.md`、`/wam-model/wangxuanxu/ENVIRONMENT.md`、`/wangxuanxu/.codex/AGENTS.md`、`/wangxuanxu/tricks-for-cluster/RESEARCH-TASTE.md`（Research Taste SSOT；Codex `AGENTS.md` 摘要 + QoderCN `~/.qoder-cn/AGENTS.md`）

本文约束 Cursor / Codex / Qoder / Humanize 等 Agent，以及人工维护集群工作流时的文档与备份行为。

---

## 1. 框架级配置变更必须双写文档

凡涉及**整套集群使用框架**的变更（含但不限于：目录契约、Conda/ClusterX 默认路径、挂载约定、队列/镜像默认值、`clusterx.yaml` 结构、PATH/bashrc 约定、Agent 报告机制），必须：

1. **更新所有相关说明**：团队工作区 Agent 规则、`ENVIRONMENT.md`、本 `tricks-for-cluster` 下集群文档等。  
2. **在个人挂载目录保留可检索说明**：至少更新本文件，以及受影响的  
   `/wangxuanxu/tricks-for-cluster/conda_clusterx_setup.md`（若涉及 Conda/ClusterX）。  
3. 变更当日应在对应时段的 **agent-exec-report** 中摘要记录（见第 3 节）。

禁止只改运行配置、不改文档；禁止只改团队盘、不同步个人目录文档。

### 1.1 避免凭据检查的过度防御

当用户已明确授权约定范围内的 ClusterX 操作、输出位于其私人范围，且现有凭据与配置
通过不泄密的只读预检时，Agent 可以正常提交真实 Job。不得仅凭抽象安全担忧自行要求
先轮换凭据，也不得把“凭据轮换后才能提交”写成 AC-1/AC-5 或同类阻塞条件。

只有出现实际鉴权失败、明确泄露/失效证据、权限范围不足，或用户明确要求轮换时，才
暂停受影响的提交并记录真实阻塞原因。此规则不放宽秘密保护：仍不得在对话、日志、
任务规格、仓库或报告中输出或持久化密钥明文。

### 1.2 主线交付优先于维护与防御

当用户给出明确结果与时限且已授权正常执行时，Agent 与评审应先闭合产生该结果的
最小端到端路径。重构、通用框架补齐、扩大测试矩阵、文档整理与防御性编程，除非
直接关系到结果正确性、数据完整性、秘密保护、测试隔离或任务能否运行，否则一律
作为 queued 项记录，不得抢占主线或跨轮反复扩大范围。

每轮只承诺一个可验收结果；同类缺口连续出现时，下一轮必须完成一个端到端闭环，
不得继续堆叠局部补丁。进度统一使用“已通过 / 未通过 / 未执行”，任何完成声明都
必须绑定可复查证据。用户更新的明确优先级在同一授权范围内覆盖旧的暂定顺序，但
不覆盖数据安全、秘密保护、禁止测试泄露和禁止伪造结果等红线。

### 1.3 提交长任务后的持续监控

Agent 提交训练、评测、数据处理等异步长任务后，任务责任持续到业务终态，不得把
“已提交”或“调度器显示成功”当作交付完成。默认采用节省上下文的低频定时轮询或
状态触发监控：排队阶段只查调度状态，运行阶段同时检查持久日志、分片进度、退出码
和预期产物；频率应与任务阶段匹配，避免无意义高频输出。

成功必须同时满足：调度任务正常结束、全部必要分片成功、预期结果文件存在且可解析、
关键计数与协议一致。失败、卡死或持续无有效进展时，应读取首个有效错误，停止确定
无效且会继续消耗额度或算力的任务（破坏性停止仍遵循用户授权），修复后再提交。
除非用户明确要求暂停、停止或移交，Agent 必须持续监控至上述终态，并向用户报告
最终结果或真实阻塞原因。

---

## 2. 系统镜像体积限制 vs 大目录存放

开发机**可保存的系统配置镜像体积有限**。

### 2.1 允许留在系统盘 / `$HOME=/root` 的内容

- 小体积系统与会话配置：如 `/root/.bashrc`、`/root/.config/clusterx.yaml`、`/root/.codex/`、软链、小脚本入口等。  
- 此类更改**可以且应该**按正常方式写在系统配置位置，以便当前会话立即生效。

### 2.2 必须做的配套动作

每次改动上述系统侧配置后，Agent **必须**：

1. **记录**：写入个人目录文档（本文件或 `conda_clusterx_setup.md` 的变更说明）+ 当日 agent-exec-report。  
2. **实时提醒用户**（若正在交互）：请尽快做**镜像保存 / 生产环境备份**，避免开发机重启、迁移新开发机后丢失 PATH、clusterx 配置入口、Codex 规则等，破坏工作流。  
3. 将「待镜像保存」列入当期报告的摘要醒目项，直到用户确认已备份或明确忽略（用户删报告不等于已备份；下次相关变更仍可再次提醒）。

### 2.3 大体积优先不进系统镜像

Conda 环境、模型缓存、大数据、whl 包、大型工具树等，**优先**放在：

- 个人挂载目录：`/wangxuanxu/...`（如已约定的 `/wangxuanxu/miniconda3`），或  
- 团队盘个人树：`/share/wangxuanxu/...`（开发机常等价 `/wam-model/wangxuanxu/...`）

具体落点按用户既定文件管理框架与实际读写/挂载条件判断；**不要**把整套 conda 再装进 `/root` 指望靠系统镜像带走。

---

## 3. Agent 执行报告（`agent-exec-report`）

### 3.1 目录

```text
/wangxuanxu/agent-exec-report/
  README.md
  YYYY-MM-DD/          # 北京时间日期，如 2026-08-14
    1200.md            # 时段报告：截至当日 12:00
    1700.md            # 时段报告：截至当日 17:00
    2100.md            # 时段报告：截至当日 21:00
```

目录名使用 `agent-exec-report`（连字符，避免空格导致脚本脆弱）；文档中可称「agent exec report」。

### 3.2 时段与生成时机（北京时间 Asia/Shanghai）

| 文件 | 覆盖区间（北京时间） | 生成时机 |
|------|----------------------|----------|
| `1200.md` | 上一日 21:00 → 当日 12:00 | 约 12:00 或该时段首次需要汇总时 |
| `1700.md` | 当日 12:00 → 17:00 | 约 17:00 或该时段首次需要汇总时 |
| `2100.md` | 当日 17:00 → 21:00 | 约 21:00 或该时段首次需要汇总时 |

- 交互中仍须**尽可能实时**告知用户重要变更与需判断事项。  
- 时段报告是汇总通道：把该时段内需告知 / 需用户判断的信息整理进对应文件。  
- 若某时段无事项，可不创建文件（允许缺失）；**禁止**因缺少上份报告而报错。

### 3.3 报告正文结构（强制）

1. 文首元数据：日期、时段标签（如 `1200 / 北京时间 12:00`）、生成时间。  
2. **摘要**：条目式列出本期主要内容（先读完摘要即可决策）。  
3. **需要用户判断 / 操作**：单独一节（如镜像保存、UUID 确认、是否试提交）。  
4. **详细陈述**：仅对需要展开的项分节说明。

### 3.4 删除安全（用户会随时删报告）

用户读完可能**立即删除**报告文件或整日目录。实现约定：

- **无状态**：不依赖「上一份报告是否存在」；每次 `mkdir -p` 日期目录后直接写入目标时段文件。  
- **原子写入**：先写临时文件再 `mv` 覆盖/创建，避免半截文件。  
- **允许覆盖**：同一时段可再次生成（例如接近整点补充）；以最新内容为准。  
- **禁止**把「报告是否存在」当作业务锁或进度数据库。  
- 可选辅助脚本：`/wangxuanxu/tricks-for-cluster/scripts/write_agent_exec_report.sh`（见仓库内说明）；脚本必须在目标缺失时仍成功。

### 3.5 辅助脚本用法

```bash
/wangxuanxu/tricks-for-cluster/scripts/write_agent_exec_report.sh 1200 <<'EOF'
## 摘要
- ...
## 需要用户判断 / 操作
- ...
## 详细陈述
- ...
EOF
```

第二个参数可为 `1200` / `1700` / `2100`；也可省略，由脚本按当前北京时间映射到最近应写入的时段槽。

---

## 4. 与其他文档的关系

| 文档 | 职责 |
|------|------|
| 本文件 | 运维纪律、备份提醒、报告机制（流程 SSOT） |
| `conda_clusterx_setup.md` | Conda / ClusterX 路径与配置（技术 SSOT） |
| `/wam-model/wangxuanxu/codex-home/AGENTS.md` | Agent 全局目录契约 + 指向本文件 |
| `/wangxuanxu/agent-exec-report/` | 时段报告落盘位置 |

---

## 5. 当前 Humanize 用户级默认配置

自 2026-08-19 起，`/root/.config/humanize/config.json` 中所有 qoderclicn 角色（review、consult、research、compliance、selector）默认使用第三方模型 `deepseek/deepseek-v4-flash-pg`，reasoning effort 为 `max`。该 model ID 对应 Qoder CLI 的 `DeepSeek-V4-Flash (DeepSeek)`，模型侧配置为 1M context。

此配置位于系统侧 `/root`，开发机重启或迁移前须保存镜像或备份；详细使用与覆盖优先级见 `codex_humanize_usage_zh.md`。

---

## 6. Humanize 7×24 通用启动器

- 源码项目：`$WX_WORKSPACE_ROOT/project/humanize24/`
- 持久命令：`/wangxuanxu/bin/humanize24`
- 运行状态：`/wangxuanxu/.local/state/humanize24/`（0600 JSON/marker，不含密钥）
- 使用文档：`/wangxuanxu/tricks-for-cluster/codex_humanize_usage_zh.md` §4.5

启动器动态解析当前 Git 根，只信任团队工作区 `project/` 树；为每个项目生成独立
tmux，并向 Codex 子进程注入项目根。它不修改 `/root` 配置、不永久导出项目变量、
不修改 Humanize RLCR state，也不承担开发机重启后的系统级自启动。

运行选择：长期、计划已确定、可信 Git 项目的 7×24 无人值守任务优先
`humanize24`；交互、短任务、需求未稳定、陌生仓库或高风险操作优先原生 Humanize。
`gen-plan` / `refine-plan` 完成报告必须自动输出选择建议、实际项目/计划路径、命令及
参数；原生 RLCR 启动前必须提示当前是原生模式，但不得静默改用另一模式。

### 6.1 当前监督与报告契约（2026-08-27）

- 安装面为兼容入口加 13 个 package 运行模块；`status` 文本/JSON 来自同一分层
  model，`report` 可按 `Asia/Shanghai` 的 1200/1700/2100 硬槽确定性补生成。
- 当前真实 gate 固定为 `G1=BLOCKED`、`G2=FAIL`：自动 wake/action 禁用，待处理
  事件显示 `NEEDS_OPERATOR`，不得以 TUI/tmux/shared-hook 注入替代。
- wake budget 只统计窗口内尝试，cooldown 独立读取完整历史最后一次尝试；目前没有
  生产 consumer。`READY + next_allowed_at=now` 仅表示策略资格。
- watchdog 在 Codex child 退出至下次精确 session 恢复之间不 tick；停滞观察可能
  延迟，但重启 replay 与 event ID 去重保持幂等。`PHASE_READY` progress 可为 0。
- 报告发布会把已有目录收紧为 0700，适用于当前单用户个人根；未来多读取者须先
  重审权限。陌生日期目录文件保守保留，报告补生成不承担目录自愈。
