# Humanize-Qoder 使用说明（中文）

在 T 集群上通过 Codex 使用 **Humanize-Qoder** 插件：由 **Codex 写代码**，**qoderclicn（Qwen3.7-Max）独立 review**，形成 RLCR 迭代循环。

**安装与 hooks 修复**见 [codex_humanize_setup.md](codex_humanize_setup.md)。本文只讲**怎么用**。

---

## 一、核心概念

### 什么是 RLCR？

**RLCR** = **Ralph-Loop with Code Review**（带代码审查的 Ralph 循环）。

在本 fork 中：

| 角色 | 工具 | 职责 |
|------|------|------|
| **实现** | Codex（`codex` / `codex-cn`） | 按 plan 改代码、跑命令、写总结 |
| **审查** | qoderclicn | 独立 review，不共用 Codex 上下文，减少盲区 |

### 四个设计理念

1. **迭代优于一次完美**：多轮小步修正，而不是指望一次生成全对。
2. **一写一审**：Codex 实现，qoderclicn 独立审查，避免「自己审自己」。
3. **Ralph 循环**：未满足验收标准前持续迭代；可选 Agent Teams 并行子任务。
4. **以终为始**：开跑前用「计划理解测验」确认你真的读过 plan（可 `--skip-quiz` 跳过）。

### 两阶段循环

```text
┌─────────────────────────────────────────────────────────────┐
│  实现阶段 (Implementation)                                     │
│  Codex 按 plan 干活 → 每轮结束写 summary → qoder 审 summary  │
│  直到标记 COMPLETE                                           │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  代码审查阶段 (Code Review)                                  │
│  qoderclicn 对相对 base 分支的 diff 打 [P0]–[P9] 严重级别   │
│  问题反馈回实现阶段，直到无遗留或达到 --max 上限              │
└─────────────────────────────────────────────────────────────┘
```

状态与日志写在项目目录 **`.humanize/`** 下，可随时打开 Markdown 文件查看进度。

---

## 二、典型工作流

```text
（可选）想法
    ↓  humanize-gen-idea
草稿 draft.md
    ↓  humanize-gen-plan
结构化 plan.md
    ↓  （可选）人工批注 + humanize-refine-plan
精炼 plan.md
    ↓  humanize-rlcr
多轮：Codex 实现 ↔ qoder review
    ↓
完成或 humanize-cancel-rlcr-loop 取消
```

### 最简三步（已有草稿时）

```bash
# 1. 生成计划（在 Codex TUI 选技能，或 shell 命令）
humanize-gen-plan --input draft.md --output docs/plan.md

# 2. （可选）根据评审批注精炼计划
humanize-refine-plan --input docs/plan.md

# 3. 启动 RLCR
humanize-rlcr docs/plan.md
```

---

## 三、在 Codex 里怎么用

### 启动 Codex

```bash
codex-cn          # 国产模型（推荐日常）
codex             # GPT-5.5 + CloseAI
```

安装或修改 hooks 后必须**新开一个 Codex 会话**。

### 方式 A：TUI 选技能（插件安装后）

在 Codex 输入 **`/skills`**，选择带前缀的技能：

| 技能名 | 作用 |
|--------|------|
| `humanize-codex-qoder:humanize-gen-idea` | 从一句话扩展多个实现方向（可选） |
| `humanize-codex-qoder:humanize-gen-plan` | 草稿 → 结构化 plan |
| `humanize-codex-qoder:humanize-refine-plan` | 处理 plan 内批注并生成 QA 台账 |
| `humanize-codex-qoder:humanize-rlcr` | **启动 RLCR 主循环** |
| `humanize-codex-qoder:humanize-cancel-rlcr-loop` | 取消当前 RLCR |
| `humanize-codex-qoder:ask-codex` | 一次性向 qoder 咨询（不进入循环） |

选中技能后，按提示传入参数（如 plan 路径），流程与下方 shell 命令一致。

### 方式 B：Shell 命令（`install-skills-codex.sh` 安装后）

若 `~/.local/bin` 在 PATH 中，可直接在项目目录执行：

```bash
humanize-gen-plan --input draft.md
humanize-refine-plan --input docs/plan.md
humanize-rlcr docs/plan.md
humanize-cancel-rlcr-loop
ask-codex "这个接口设计有没有明显问题？"
```

### 中文 prompt 输入

Cursor SSH 终端里 IME 常失效。优先：

- **Windows 用微软拼音（或 Rime），不要用搜狗/百度**——聊天框能打中文、远端终端不能时，只换输入法即可；已验证无需改 Cursor 设置、无需在集群装输入法
- TUI 内 **粘贴** 中文（`Ctrl+Shift+V`）
- 用 **`codex-cn-ask "中文问题"`** 发非交互任务（见 [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md)）

Codex **回复**默认简体中文（`~/.codex/AGENTS.md`）。

---

## 四、命令详解

### 4.1 `humanize-gen-idea`（可选）

从模糊想法生成多方向草稿。

```bash
humanize-gen-idea "给编辑器加 undo/redo"
humanize-gen-idea --n 4 existing-notes.md
```

- 默认输出：`.humanize/ideas/<slug>-<timestamp>.md`
- `--n`：并行探索方向数（默认 6）

### 4.2 `humanize-gen-plan`

把草稿变成可执行的实现计划（含验收标准、任务拆分）。

```bash
humanize-gen-plan --input draft.md
humanize-gen-plan --input draft.md --output docs/plan.md
humanize-gen-plan --input draft.md --discussion    # 与 qoder 多轮收敛（默认）
humanize-gen-plan --input draft.md --direct        # 跳过收敛，直接出 plan
humanize-gen-plan --input draft.md --auto-start-rlcr-if-converged  # 收敛后自动开 RLCR
```

**流程概要**：校验路径 → 检查与仓库相关性 → 分析草稿清晰度 → 与用户澄清 → 生成 `plan.md`。

**输出默认路径**：`.humanize/plans/<draft-slug>-<timestamp>.md`

### 4.3 `humanize-refine-plan`

处理 plan 里的**评审批注**，去掉批注块，生成 QA 台账。

```bash
humanize-refine-plan --input docs/plan.md
humanize-refine-plan --input docs/plan.annotated.md --output docs/plan.refined.md
humanize-refine-plan --input docs/plan.md --direct --alt-language zh
```

**支持的批注格式**（可混用）：

```markdown
行内：文字 CMT: 请说明 AC-3 为何拆分 ENDCMT 后续文字

块级：
CMT:
请确认 task4 与 task5 的依赖关系。
ENDCMT

短标签：<cmt>同上</cmt>
长标签：<comment>同上</comment>
```

**QA 输出默认**：`.humanize/plan_qa/plan-qa.md`（含 Summary、Comment Ledger、Answers 等）。

`--alt-language zh` 会额外生成 `plan_zh.md`、`plan-qa_zh.md` 等翻译版。

### 4.4 `humanize-rlcr`（主命令）

```bash
humanize-rlcr docs/plan.md
humanize-rlcr --plan-file docs/plan.md --max 20
humanize-rlcr docs/plan.md --yolo
humanize-rlcr docs/plan.md --skip-quiz
humanize-rlcr --skip-impl --base-branch main   # 跳过实现，直接 code review
```

| 参数 | 说明 |
|------|------|
| `--max N` | 最大迭代轮数（默认 42） |
| `--codex-model MODEL:EFFORT` | 实现侧模型元数据（默认 `gpt-5.5:high`）；用 `codex-cn` 时以 TUI `/model` 为准 |
| `--codex-timeout` / `--qoder-timeout` | 单次 qoder review 超时秒数（默认 5400） |
| `--base-branch BRANCH` | code review 对比的基线分支（默认自动：remote 默认 → main → master） |
| `--full-review-round N` | 每 N 轮做一次 Full Alignment Check（默认 5，最小 2） |
| `--track-plan-file` | 将 plan 纳入 git 跟踪（要求工作区干净） |
| `--push-every-round` | 每轮结束后要求 `git push`（默认只本地 commit） |
| `--skip-impl` | 跳过实现阶段，直接进入 diff review |
| `--claude-answer-codex` / `--auto-answer-qoder-questions` | qoder 提出 Open Questions 时由 Codex 自行继续，不弹窗问用户 |
| `--agent-teams` | 启用 Codex 子 agent 并行实现（review 仍由 qoder 做） |
| `--skip-quiz` | 跳过「计划理解测验」 |
| `--yolo` | `--skip-quiz` + `--claude-answer-codex`（全自动） |

#### 计划理解测验（Plan Understanding Quiz）

启动 `humanize-rlcr` 时，会先出 **两道选择题**，考查你是否理解 plan 的技术要点：

1. 哪些组件在变、怎么变？
2. 各模块如何衔接？

- 全对 → 立即进入循环  
- 有错 → 解释 plan 要点，可选继续或停下重读  
- 非强制关卡，但强烈建议认真做，避免「愿望式编程」跑几十轮错误 plan  

跳过方式：`--skip-quiz` 或 `--yolo`；`gen-plan --auto-start-rlcr-if-converged` 也会自动跳过。

#### Stop hook 如何驱动循环

每轮 Codex 试图结束时，**`~/.codex/hooks.json`** 里的 Stop hook 会：

1. 检查本轮是否有合格 summary  
2. 调用 qoderclicn review  
3. 未通过则阻止退出，注入下一轮 prompt  

因此 **hooks 必须正确配置**（见 [codex_humanize_setup.md](codex_humanize_setup.md)）。

### 4.5 无人值守 / 全权限运行（7×24）

目标：计划与目标定好后，让 Humanize **长时间自主迭代**，避免因 **Codex 命令审批**、**qoder 工具权限询问**、**计划测验 / Open Questions 等人机交互** 而中断。

> **风险**：下面配置等于允许 agent 在仓库内几乎任意读写与执行命令。只在**可信仓库、隔离开发机**使用；不要对不可信代码或生产密钥目录开。

#### 三层权限（缺一仍可能卡住）

| 层 | 负责什么 | 无人值守怎么开 |
|----|----------|----------------|
| **A. Humanize 流程** | 计划测验、qoder Open Questions 是否问人 | `humanize-rlcr … --yolo` |
| **B. Qoder 审查** | 无头 review 时 Read/Grep 等工具权限 | 默认已 bypass（见下） |
| **C. Codex 实现** | shell / 写文件是否弹审批、沙箱是否拦网 | `approval_policy=never` + 宽松 sandbox |

只开 `--yolo` **不够**：那只覆盖 A；本机默认 Codex 仍可能是「问用户审批」（`approvals_reviewer = "user"`），长跑时会卡在审批提示上。

#### A. Humanize：`--yolo`

```bash
humanize-rlcr docs/plan.md --yolo
# 等价于：--skip-quiz + --claude-answer-codex
```

效果：

- 跳过「计划理解测验」
- qoder 提出 Open Questions 时由 **Codex 自行继续**，不再等你在 TUI 回答

可选参数（长跑常用）：

```bash
humanize-rlcr docs/plan.md --yolo --max 80
humanize-rlcr docs/plan.md --yolo --privacy          # 跳过方法论分析阶段
humanize-rlcr docs/plan.md --yolo --qoder-model deepseek/deepseek-v4-flash-pg:max
```

在 Codex TUI：`/skills` → `humanize-codex-qoder:humanize-rlcr`，参数里同样加上 `--yolo`。

#### B. Qoder：默认已无询问

Humanize 的 `ask-qoder.sh` 默认：

```bash
HUMANIZE_QODER_BYPASS_PERMISSIONS=1   # 默认
# → qoderclicn --permission-mode bypass_permissions
```

一般**无需改**。若环境里被关掉，启动 Codex / RLCR 前：

```bash
export HUMANIZE_QODER_BYPASS_PERMISSIONS=1
```

T 集群出站（Authentik）仍建议保证代理可用（见上文「集群相关环境变量」）；审查失败优先查 [codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md)，那不是权限弹窗问题。

#### C. Codex：无审批 + 宽松沙箱

**本机推荐默认**（已可写入 `~/.codex/config.toml`）：

```toml
# 无人值守：不向用户索取命令审批；沙箱放开（危险）
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

含义简表：

| 配置 / 启动参数 | 作用 |
|-----------------|------|
| `approval_policy = "never"` 或 `-a never` | 永不向用户要审批；失败回给模型重试 |
| `sandbox_mode = "danger-full-access"` 或 `-s danger-full-access` | 几乎不限制命令执行环境 |
| `--dangerously-bypass-approvals-and-sandbox` | 一次性跳过审批**与**沙箱（更激进；仅隔离环境） |
| `--approve-for-me` | 自动审批准入（仍偏交互/半自动，不适合纯 7×24） |

**单次会话覆盖**（不想改全局默认时）：

```bash
codex --ask-for-approval never --sandbox danger-full-access
codex-cn --ask-for-approval never --sandbox danger-full-access
```

**临时恢复「要问人」**（同一机器做交互调试时）：

```bash
codex --ask-for-approval on-request --sandbox workspace-write
```

并确认：

1. 项目目录在 `~/.codex/config.toml` 的 `[projects."…"]` 中为 `trust_level = "trusted"`（陌生目录会先问信任）。
2. `[features] hooks = true`，且 `~/.codex/hooks.json` 的 Stop hook 已信任并启用（否则 RLCR 不会自动进入下一轮 review）。

#### 推荐 7×24 启动流程

```bash
# 0. 代理 / 登录（按你用的实现端）
# GPT: 直接 codex（包装会 openai_on）
# 国产: domestic_proxy_on 或 codex-cn

# 1. 用 tmux 防止 SSH 断开带走会话
tmux new -s humanize
cd /path/to/your/repo

# 2. 启动无人值守 Codex（若已写进 config.toml，可省略长参数）
codex --ask-for-approval never --sandbox danger-full-access
# 或: codex-cn --ask-for-approval never --sandbox danger-full-access

# 3. 在 TUI 中启动 RLCR（计划已审阅）
# /skills → humanize-rlcr
# 参数示例：
#   docs/plan.md --yolo --max 80
```

##### humanize24 的 Codex 专用出口

在 T 集群上，`humanize24` 直接执行 Codex 二进制，不经过 `.bashrc` 的 `codex()`
函数。必须确保启动器专用代理指向 CloseAI，而不是通用 Authentik 出口：

```bash
export HUMANIZE24_CODEX_PROXY="$CLOSEAI_PROXY_ADDR"
humanize24 doctor --project /path/to/project
```

`doctor` 应显示 `[OK] codex-proxy: http://closeai-proxy.pjlab.org.cn:23128`。
该值只注入 Codex 子进程且不写入 state；qoderclicn Stop hook 仍使用自己的
Authentik 代理配置。

另开一个终端看进度（见「五、监控进度」），例如：

```bash
# 按你安装的 humanize 监控入口；或直接看状态文件
ls -lt .humanize/rlcr/*/
```

取消循环：在 Codex 里跑 `humanize-cancel-rlcr-loop`，或 TUI 选同名技能。

#### 仍可能中断的原因（不是权限弹窗）

| 原因 | 处理 |
|------|------|
| qoder `Not logged in` / 403 / auth 被 wipe | [codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md) |
| API 额度 / 模型不可用 | 换 profile 或 `--qoder-model` / Codex `/model` |
| tmux / 开发机被回收 | 用持久镜像 + tmux；必要时 `tmux attach -t humanize` |
| hooks 未生效 | `fix_humanize_codex_hooks.sh` 后**新开** Codex 会话 |
| `--max` 轮数用尽 | 加大 `--max` 或根据 review 结果改 plan 再开一轮 |

#### 快速对照：交互 vs 无人值守

| 场景 | Humanize | Codex | Qoder |
|------|----------|-------|-------|
| 日常一起看 | `humanize-rlcr plan.md` | 默认 / `on-request` | 默认 bypass |
| 定好 plan 后挂机 | `… --yolo` | `never` + `danger-full-access` | 保持默认 bypass |

### 4.6 `humanize-cancel-rlcr-loop`

```bash
humanize-cancel-rlcr-loop
```

或在 TUI 选 `humanize-codex-qoder:humanize-cancel-rlcr-loop`。

### 4.7 `ask-codex`

一次性 qoder 咨询，**不进入 RLCR**。

```bash
ask-codex "这个缓存策略在高并发下有什么风险？"
ask-codex --qoder-model Qwen3.7-Max --qoder-effort xhigh "审查 API 设计"
```

输出保存在 `.humanize/skill/<timestamp>/`（`input.md`、`output.md`、`metadata.md`）。

---

## 五、监控进度

在**另一个终端**：

```bash
# 一次性加入 shell（可写入 ~/.bashrc）
source ~/.agents/skills/humanize/scripts/humanize.sh

humanize monitor rlcr      # 当前 RLCR 循环
humanize monitor skill     # 所有 skill 调用
humanize monitor codex     # ask-codex / qoder 咨询
```

每轮 RLCR 数据目录：`.humanize/rlcr/<timestamp>/`。

---

## 六、配置

配置优先级（从低到高）：

1. 插件默认 `config/default_config.json`
2. 用户 `~/.config/humanize/config.json`
3. 项目 `.humanize/config.json`
4. 命令行参数

### 常用配置项

| 键 | 默认值 | 说明 |
|----|--------|------|
| `codex_model` | `gpt-5.5` | 实现侧模型元数据 |
| `codex_effort` | `high` | 实现侧 reasoning effort |
| `qoder_review_model` | `Qwen3.7-Max` | RLCR review 模型 |
| `qoder_review_effort` | `xhigh` | RLCR review 力度 |
| `qoder_consult_model` | `Qwen3.7-Max` | ask-codex 模型 |
| `gen_plan_mode` | `discussion` | `discussion` 或 `direct` |
| `agent_teams` | `false` | 默认是否开 Agent Teams |
| `alternative_plan_language` | `""` | 如 `zh` 生成中文 plan 变体 |

**不必手改 JSON 的指定方式（推荐）：**

```bash
# 仅本次 RLCR 会话（写入该次 state.md，Stop hook 会传给 qoder）
humanize-rlcr plans/foo.md --qoder-model deepseek/deepseek-v4-flash-pg --qoder-effort high

# 与 Qoder TUI 一致可用 max（比 xhigh 更高）
humanize-rlcr plans/foo.md --qoder-model deepseek/deepseek-v4-flash-pg:max

# 本次会话 + 写入项目 .humanize/config.json（以后本仓库默认用它）
humanize-rlcr plans/foo.md --qoder-model deepseek/deepseek-v4-flash-pg --persist-qoder-config

# 不启动 RLCR，只改「本项目」默认 review 模型（也可热补丁当前 state.md）
bash ~/.agents/skills/humanize/scripts/set-qoder-review-model.sh deepseek/deepseek-v4-flash-pg max
```

环境变量（启动 setup 时生效）：`HUMANIZE_QODER_REVIEW_MODEL`、`HUMANIZE_QODER_REVIEW_EFFORT`。

qoder effort 合法值与 `qoderclicn --reasoning-effort` 对齐：`none|low|medium|high|xhigh|max`（TUI 里 DeepSeek 的 **max** 即此处 `max`，不是 Codex 的 `xhigh`）。

优先级（review 模型）：**CLI `--qoder-model` > 环境变量 > 项目/用户 config > 插件默认**。

**项目级覆盖**示例（`.humanize/config.json`）：

```json
{
  "codex_model": "deepseek-v4-flash",
  "codex_effort": "high",
  "qoder_review_model": "Qwen3.7-Max",
  "qoder_review_effort": "xhigh"
}
```

### 集群相关环境变量（qoder 出站）

Humanize 对 qoderclicn 子进程单独处理代理（见 `scripts/lib/qoder-cli.sh`）：

| 变量 | 说明 |
|------|------|
| `HUMANIZE_QODER_CLI` | 覆盖 reviewer 命令（默认 `qoderclicn`） |
| `HUMANIZE_QODER_PROXY_MODE` | `auto`（默认）/ `always` / `never` / `inherit` |
| `HUMANIZE_QODER_PROXY_URL` | H 集群 headless 代理 URL |
| `HUMANIZE_QODER_BYPASS_PERMISSIONS` | 默认 `1`；设为 `0` 关闭 qoder 无头模式的 bypass |

**T 集群注意**：计算节点不能直连外网，访问 `gateway.qoder.com.cn` 需 **Authentik 代理**（`proxy_on`，即 `~/.bashrc` 中的 `PROXY_URL`）。交互式 `qoderclicn` 的 wrapper 会自动注入代理；若仍报 `Unable to connect`，先手动 `proxy_on` 再启动。

Humanize 在 T 分区默认 `HUMANIZE_QODER_PROXY_MODE=auto` 会**清除**代理（为 H 集群设计）。在 T 集群跑 RLCR 时请设置：

```bash
export HUMANIZE_QODER_PROXY_MODE=always
export HUMANIZE_QODER_PROXY_URL="$PROXY_URL"   # 或 proxy_on 后 echo $http_proxy
```

T 分区一般走 `auto` 分支；qoder 需能访问外网 API。

### qoderclicn 默认简体中文回复

已安装 **`~/.local/bin/qoderclicn` wrapper**，对所有 qoderclicn 调用（含 Humanize RLCR review、`ask-codex`）自动追加：

```text
始终用简体中文回复用户，除非用户明确要求使用其他语言。…
```

**安装 / 重装**（qoder 升级后若 wrapper 被覆盖，或二进制曾被破坏，可再跑）：

```bash
# 若 qoderclicn 无法启动，先强制重装官方二进制，再装 wrapper
proxy_on
curl -fsSL https://qoder.com.cn/install | bash -s -- --force
bash ~/tricks-for-cluster/setup_qoderclicn_zh.sh
```

> **注意**：`setup_qoderclicn_zh.sh` 会先 `rm` 掉 `~/.local/bin/qoderclicn` 再写入 wrapper 脚本，避免对 symlink 直接重定向而**覆盖真实二进制**。

| 文件 | 作用 |
|------|------|
| `~/.local/bin/qoderclicn` | wrapper 脚本 |
| `~/.local/bin/.qoderclicn-real` | 指向真实 qoderclicn 二进制 |
| `~/.config/humanize/config.json` | `qoder_append_system`（与 Codex 中文偏好对齐） |

自定义提示词（临时）：

```bash
export QODERCLICN_APPEND_SYSTEM_PROMPT="你的系统提示"
```

与 Codex 侧配置对照见 [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md)「Codex 默认中文回复」。

---

## 七、与 Codex 其它能力配合

| 场景 | 建议 |
|------|------|
| 日常实现用国产模型 | 先 `codex-cn`，TUI `/model` 选 DeepSeek 等；RLCR 实现走当前 Codex 会话模型 |
| 实现用 GPT | `codex` + CloseAI |
| Humanize 插件技能 | `/skills` 选 `humanize-codex-qoder:*` |
| 中文输入困难 | Windows 换微软拼音（勿用搜狗）；或粘贴 / `codex-cn-ask` |
| hooks 报警 | `bash ~/tricks-for-cluster/fix_humanize_codex_hooks.sh` |

---

## 八、常见问题

| 现象 | 处理 |
|------|------|
| `/skills` 里看不到 Humanize | `codex plugin list` 确认已安装；**新开会话** |
| RLCR 一轮就停、无 review | 检查 `~/.codex/hooks.json` 与 `[features] hooks = true`；跑 `fix_humanize_codex_hooks.sh` |
| qoder review 超时 / 失败 | 确认 `qoderclicn` 已登录；看 `.humanize/` 下日志。反复 `Not logged in`、恢复后又被清空：见 [codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md) |
| plan 测验看不懂 | 先读 plan 再跑；或 `--skip-quiz` / `--yolo` |
| 长跑被 Codex 审批弹窗打断 | 用 `approval_policy=never` + 宽松 sandbox，见 **4.5 无人值守**；启动加 `--yolo` |
| 想跳过方法论分析 | `humanize-rlcr plan.md --privacy` |
| 方法论阶段要求 Opus / 模型不可用 | Codex+qoder 版已改为使用当前会话可用的 Codex 模型，不再硬编码 Claude Opus；升级/同步 `~/.agents/skills/humanize` 后生效 |
| 插件升级后 hooks 又报错 | 升级 → `install-skills-codex.sh` → `fix_humanize_codex_hooks.sh` |

---

## 九、文件与目录约定

| 路径 | 内容 |
|------|------|
| `.humanize/plans/` | gen-plan 生成的计划 |
| `.humanize/plan_qa/` | refine-plan 的 QA 台账 |
| `.humanize/ideas/` | gen-idea 输出 |
| `.humanize/rlcr/<ts>/` | 单次 RLCR 会话状态 |
| `.humanize/skill/<ts>/` | ask-codex 等单次 skill 记录 |
| `.humanize/config.json` | 项目级 Humanize 配置 |

---

## 相关文档

- [codex_humanize_setup.md](codex_humanize_setup.md) — 安装、SSH、hooks 修复、升级
- [codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md) — 登录/403/凭据 wipe 与成功调用流程
- [codex_humanize_kubebrain_incident_log_2026-08.md](codex_humanize_kubebrain_incident_log_2026-08.md) — 2026-08 问题与方案总表
- [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md) — Codex 代理、中文回复与输入
- [codex_domestic_models_setup.md](codex_domestic_models_setup.md) — `codex-cn` 国产模型
- 上游英文：`~/.codex/.tmp/marketplaces/humanize-codex-qoder/docs/usage.md`
