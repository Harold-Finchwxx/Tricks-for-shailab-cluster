# Humanize / qoderclicn（Kubebrain）问题与解决方案汇总（2026-08）

本文汇总在镜像机（`HOME`/`/root`）+ PVC（`/wangxuanxu`）环境下，将 **Humanize** 从 Claude 协作形态迁到 **Codex + qoderclicn** 后，Smoke / 全流程跑通中暴露的问题、根因与已落地修复。

**文档位置（请两边同步维护）：**

- `/root/tricks-for-cluster/`
- `/wangxuanxu/tricks-for-cluster/`
- GitHub：[`Harold-Finchwxx/Tricks-for-shailab-cluster`](https://github.com/Harold-Finchwxx/Tricks-for-shailab-cluster)

**相关专题文档：**

| 文档 | 侧重 |
|------|------|
| [codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md) | 登录 / 403 / 凭据 wipe 与审查成功判定 |
| [codex_humanize_setup.md](codex_humanize_setup.md) | 安装与 hooks |
| [codex_humanize_usage_zh.md](codex_humanize_usage_zh.md) | 日常用法、`--qoder-model`、effort=`max`、**无人值守 / 全权限（§4.5）** |
| `setup_qoderclicn_zh.sh` | qoder wrapper（HOME / 代理 / auth 回填） |

**运行时修复落点（非本仓库）：** `~/.agents/skills/humanize/`  
默认回推个人 fork：[`Harold-Finchwxx/humanize-codex-qoder`](https://github.com/Harold-Finchwxx/humanize-codex-qoder)（**不要**默认直推合作者 [`HaoyiZhu/humanize-codex-qoder`](https://github.com/HaoyiZhu/humanize-codex-qoder)）。

---

## 0. 环境背景

| 项 | 说明 |
|----|------|
| 实现端 | Codex CLI（如 `gpt-5.6-sol`） |
| 审查端 | `qoderclicn`（默认曾为 `Qwen3.7-Max`；可 BYOK DeepSeek 等） |
| 出站 | Authentik `PROXY_URL`（如 `10.1.20.50:23128`） |
| 双树 | 工具/认证宜在 `/root`；PVC `/wangxuanxu` 作数据与 auth mirror |
| Smoke | `/wangxuanxu/humanize-smoke-test`（**独立 git repo**） |

---

## 1. 问题清单总表

| # | 现象 | 根因（简述） | 解决方案（简述） |
|---|------|--------------|------------------|
| A | Stop hook 报 `Not logged in` / review 2s 失败 | `HOME` 指到 PVC → 错用 `/wangxuanxu/.qoder-cn`；或 hook 代理不完整 → gateway **403** → CLI `automatic_auth_rejection` **清空** `/root/.qoder-cn/.auth` | Wrapper + Stop hook **强制 `HOME=/root`**、强制 Authentik 代理；wipe 后从 `.auth-backup`/PVC **自动回填** |
| B | 浏览器 `qoderclicn login` 空等 / 超时 | 其实是 A 的连锁；或 device flow 5 分钟未确认 | 优先恢复 auth，取消悬挂 login；仅 backup 皆空时再 login |
| C | 独立复审 COMPLETE 但 `review_started: false` | 审查结果未被子消费（前面 hook 失败卡住） | 修好 A 后正常结束轮次，让原生 Stop 推进 |
| D | 无法为本项目指定 review 模型（只能改全局 JSON） | `humanize-rlcr` 无 `--qoder-model`；Stop 未把模型传给 ask-qoder | 增加 `--qoder-model` / `--qoder-effort` / `--persist-qoder-config`；`state.md` 持久化；helper `set-qoder-review-model.sh` |
| E | `:max` 被拒（Qoder TUI 可选 max） | Humanize 只认 `xhigh\|high\|medium\|low` | qoder effort 对齐 `none\|low\|medium\|high\|xhigh\|max` |
| F | 方法论阶段硬要求 Opus，本机无该模型 | Claude 时代 prompt/agent 遗留 | 改为 Codex 可用模型；quiz/合规检查同步去 Claude 硬编码 |
| G | agent 元数据误用偏弱的 `gpt-5.4` | 去 Opus 时的保守占位 | quiz → `gpt-5.6-sol`；合规 → `gpt-5.5`（调用方仍可优先用会话模型） |

---

## 2. 分项：原因与改进

### A / B / C — qoder 登录失败、凭据被清空、审查卡住

**原因链：**

1. Codex/hook 常继承 `HOME=/wangxuanxu`，与 `/root/.qoder-cn` 双 store。
2. hook 未继承完整 Authentik 代理时，`getUserInfo` / gateway 返回 **HTTP 403**。
3. `qoderclicn` 将 403 视为鉴权失败：`credential.clear reason=automatic_auth_rejection`，删除 `user` 凭据。
4. 下一次表现为 `Not logged in`；Codex 误走浏览器 login；独立复审即使已有 COMPLETE，状态也停在 `review_started: false`。

**改进：**

- `/root/.local/bin/qoderclicn` wrapper：`HOME=/root`、始终注入 `PROXY_URL`、auth backup/restore。
- `loop-codex-stop-hook.sh` / `qoder-cli.sh`：pin HOME、PATH、强制代理。
- 排障与成功判定见 [codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md)。

**验收：** 长时 qoder 调用（数十秒+）、`COMPLETE` / diff review PASS、`finalize-summary` 通过。Smoke 中审查通过且**无因 findings 改产品代码**。

### D — 本项目 / 本次会话指定 review 模型

**原因：** 配置优先级虽支持项目 `.humanize/config.json`，但缺少「启动时一条命令」入口；Stop hook 只 `--role review`，不传 `--qoder-model`。

**改进：**

```bash
humanize-rlcr plan.md --qoder-model deepseek/deepseek-v4-flash-pg:max
humanize-rlcr plan.md --qoder-model ... --persist-qoder-config   # 写入项目 config
bash ~/.agents/skills/humanize/scripts/set-qoder-review-model.sh MODEL [effort]
```

写入 `state.md` 的 `qoder_review_model` / `qoder_review_effort`，Stop → `ask-qoder.sh` 透传。modelID 允许含 `/`。

### E — reasoning effort `max`

**原因：** Qoder / `qoderclicn` 合法值为 `none|low|medium|high|xhigh|max`（`max` 高于 `xhigh`）；Humanize 校验过窄。

**改进：** ask-qoder / setup-rlcr / helper / 文档一律接受 `max`。

### F / G — Claude Opus 遗留与模型档位

**原因：** 方法论 prompt、incomplete 文案、quiz/合规 agent 仍写 `opus`/`sonnet`。去硬编码时曾暂用 `gpt-5.4`。

**改进：**

- 方法论：使用**当前会话可用 Codex 模型**，禁止再要求 Opus。
- quiz 默认 `gpt-5.6-sol`；合规默认 `gpt-5.5`。
- `start-rlcr-loop.md` 仍要求优先覆盖为**当前会话模型**。
- 不需要该阶段：`humanize-rlcr ... --privacy`。

---

## 3. 推荐操作速查

```bash
# 审查模型（本次）
humanize-rlcr plans/x.md --qoder-model deepseek/deepseek-v4-flash-pg:max

# 登录健康
HOME=/root PATH=/root/.local/bin:$PATH qoderclicn status

# 紧急恢复凭据（勿打印 token）
cp -f /wangxuanxu/.qoder-cn/.auth/user /root/.qoder-cn/.auth/user
chmod 600 /root/.qoder-cn/.auth/user

# 跳过方法论分析
humanize-rlcr plans/x.md --privacy
```

---

## 4. 维护约定

1. **文档**：改 `tricks-for-cluster` 后同步 `/root` 与 `/wangxuanxu`，并推送本 GitHub 仓。
2. **技能代码**：改 `~/.agents/skills/humanize` 后同步 PVC 副本，并回推个人 fork  
   **`Harold-Finchwxx/humanize-codex-qoder`**（`git@github.com:Harold-Finchwxx/humanize-codex-qoder.git`）。  
   **不要**默认直推合作者仓库 `HaoyiZhu/humanize-codex-qoder`；上游合并由个人 fork 发 PR / 另行协商。
3. **升级插件**后复查：HOME/proxy/auth-backup、`--qoder-model`、`max` effort、方法论非 Opus 文案是否被上游覆盖冲掉。

---

## 5. 变更文件索引（本轮）

### tricks-for-cluster（本仓）

- 本文件（汇总）
- `codex_qoder_auth_and_review_troubleshoot.md`（新建/充实）
- `codex_humanize_usage_zh.md`（`--qoder-model`、`max`、FAQ）
- `codex_humanize_setup.md`（交叉引用、方法论说明）
- `README.md`（目录条目）
- `setup_qoderclicn_zh.sh`（wrapper：HOME / 代理 / auth 回填，以 PVC 版为准对齐）

### humanize 技能（上游仓）

- `scripts/setup-rlcr-loop.sh`、`ask-qoder.sh`、`ask-codex.sh`、`set-qoder-review-model.sh`
- `hooks/loop-codex-stop-hook.sh`、`hooks/lib/loop-common.sh`、`hooks/lib/methodology-analysis.sh`、`hooks/loop-read-validator.sh`
- `scripts/lib/qoder-cli.sh`（若含 HOME/proxy 强化）
- `commands/start-rlcr-loop.md`、`SKILL.md`
- `agents/plan-understanding-quiz.md`、`agents/plan-compliance-checker.md`
- `prompt-template/**/methodology-analysis-prompt.md`、`block/methodology-analysis-state-file-modification.md`
