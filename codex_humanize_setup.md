# Codex + Humanize-Qoder 插件（集群）

在 T 集群上使用 [humanize-codex-qoder](https://github.com/HaoyiZhu/humanize-codex-qoder)：**Codex 实现代码，qoderclicn 独立 review**（RLCR 循环）。

---

## 架构

```text
humanize-rlcr  →  Codex 按 plan 实现  →  Stop hook 触发  →  qoderclicn review
                      ↑                                      ↑
                 codex / codex-cn                      ~/.codex/hooks.json
```

| 组件 | 路径 / 命令 |
|------|-------------|
| 插件 marketplace | `git@github.com:HaoyiZhu/humanize-codex-qoder.git`（**私有 repo**，需 SSH） |
| 用户 skills + runtime | `~/.agents/skills/`、`~/.agents/skills/humanize/` |
| Stop hook | `~/.codex/hooks.json` |
| Review CLI | `qoderclicn`（`~/.local/bin/qoderclicn`） |
| 实现 CLI | `codex`（GPT + CloseAI）或 `codex-cn`（国产模型，见 [codex_domestic_models_setup.md](codex_domestic_models_setup.md)） |

---

## 一、前置条件

1. **Codex CLI** 已安装（见 [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md)）
2. **GitHub SSH 密钥** 已加到**你的** GitHub 账号（私有 repo 协作者身份）
3. **qoderclicn** 已安装并登录（review 端；实现端用 Codex 即可）

```bash
ssh -T git@github.com          # 应看到 Hi <username>!
command -v qoderclicn
command -v codex
```

## 当前部署基线（2026-08-26）

| 安装位置 | 当前版本 | 更新命令 |
|----------|----------|----------|
| root：`/root/node/node-v22/bin/codex` | `0.149.1` | `npm install -g @openai/codex@0.149.1` |
| 个人 PVC：`/wangxuanxu/node/node-v22/bin/codex` | `0.149.1` | `npm install -g --prefix /wangxuanxu/node/node-v22 @openai/codex@0.149.1` |

当前交互式 shell 的 PATH 优先命中 root 安装。Humanize 与 Humanize24 均通过 PATH
调用 `codex`，不固定 CLI 版本；更新前应分别运行两套 `humanize24 doctor`，确认
`hooks`、`qoderclicn`、Stop hook 与代理检查通过。

2026-08-26 更新前的可执行回滚备份位于：

```text
/wangxuanxu/codex-backups/20260826-pre-0.149.1/root-codex-0.147.0
/wangxuanxu/codex-backups/20260826-pre-0.149.1/personal-codex-0.142.3
```

---

## 二、安装插件 marketplace

`codex plugin marketplace add` 会通过 git clone 拉仓库。**私有 repo 必须用 SSH**，且 clone 时不要走 CloseAI（对 GitHub 会 403）：

```bash
openai_off    # 或确保未 export http_proxy
codex plugin marketplace add git@github.com:HaoyiZhu/humanize-codex-qoder.git --ref main
codex plugin add humanize-codex-qoder@humanize-codex-qoder
codex plugin list   # 期望: installed, enabled
```

若尚未配置 SSH，见 [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md) 同目录下集群惯例：在 `~/.ssh/` 生成 `id_ed25519` 并把公钥加到 GitHub → Settings → SSH keys。

---

## 三、完整安装（skills + hooks）

插件 marketplace **只装技能包**；RLCR 循环还需要 **用户级 skills/runtime + Stop hook**。

**不要用** `./install.sh`（CentOS 7 / bash 4.2 下无参数运行会报 `ORIGINAL_ARGS[@]: unbound variable`）。请用：

```bash
bash ~/.codex/.tmp/marketplaces/humanize-codex-qoder/scripts/install-skills-codex.sh --target codex
```

安装结果：

| 内容 | 位置 |
|------|------|
| Skills | `~/.agents/skills/humanize-*`、`ask-codex` 等 |
| Runtime | `~/.agents/skills/humanize/{hooks,scripts,prompt-template,...}` |
| Stop hook | 合并进 `~/.codex/hooks.json` |
| Feature | `[features] hooks = true` in `~/.codex/config.toml` |

### qoderclicn 默认中文回复

```bash
# 二进制损坏时先: curl -fsSL https://qoder.com.cn/install | bash -s -- --force
bash ~/tricks-for-cluster/setup_qoderclicn_zh.sh
```

为 `qoderclicn` 安装 wrapper（须先 `rm` 旧 symlink 再写脚本，勿覆盖真实二进制）。Humanize review / `ask-codex` 默认输出简体中文。详见 [codex_humanize_usage_zh.md](codex_humanize_usage_zh.md)。

---

## 四、Codex 0.142.3 时代的兼容性修正

Humanize 安装脚本与插件缓存中的 hooks 配置含 **`description` 字段**（Claude Code 格式），Codex 0.142.x **只接受** `{ "hooks": { ... } }`，否则会报警且 **Stop hook 不生效**。

### 症状

```text
failed to parse hooks config .../hooks.json: unknown field `description`, expected `hooks`
failed to parse plugin hooks config .../plugins/cache/.../hooks/hooks.json: ...
[features].codex_hooks is deprecated. Use [features].hooks instead.
```

### 一键修复

```bash
bash ~/tricks-for-cluster/fix_humanize_codex_hooks.sh
```

脚本会：

1. 从 `~/.codex/hooks.json` 去掉 `description`（保留 `hooks` 结构）
2. 将 `config.toml` 中 `codex_hooks` 改为 `hooks = true`
3. 将插件缓存里 Claude 格式的 `hooks/hooks.json` 改名为 `.bak`

**插件升级后**若警告复现，再跑一次上述脚本即可。

### 手动修复（参考）

```bash
# 1. hooks.json 仅保留 hooks 键（无 description）
# 2. config.toml
#    [features]
#    hooks = true
# 3. 插件缓存
mv ~/.codex/plugins/cache/humanize-codex-qoder/humanize-codex-qoder/*/hooks/hooks.json \
   ~/.codex/plugins/cache/humanize-codex-qoder/humanize-codex-qoder/*/hooks/hooks.json.bak
```

---

## 五、使用（概要）

完整中文使用说明见 **[codex_humanize_usage_zh.md](codex_humanize_usage_zh.md)**（命令、参数、RLCR 流程、配置、监控、FAQ）。

### 快速开始

```bash
codex-cn                    # 或 codex；新开 Codex 会话
# TUI: /skills → humanize-codex-qoder:humanize-gen-plan / humanize-rlcr 等

humanize-gen-plan --input draft.md --output docs/plan.md
humanize-refine-plan --input docs/plan.md    # 可选
humanize-rlcr docs/plan.md
```

| 技能 / 命令 | 用途 |
|-------------|------|
| `humanize-gen-plan` | 草稿 → 结构化 plan |
| `humanize-refine-plan` | 处理 plan 批注 |
| `humanize-rlcr` | 启动 RLCR 主循环 |
| `humanize-cancel-rlcr-loop` | 取消循环 |
| `ask-codex` | 一次性 qoder 咨询 |

常用参数：`--yolo`（流程全自动）、`--skip-quiz`（跳过计划测验）、`--max N`（最大轮数）。

**7×24 无人值守**（避免 Codex/qoder 权限询问打断）：见 [codex_humanize_usage_zh.md](codex_humanize_usage_zh.md) **§4.5**（`--yolo` + Qoder bypass + Codex `approval_policy=never` / `sandbox_mode=danger-full-access`）。

---

## 六、常见问题

| 现象 | 处理 |
|------|------|
| `Permission denied (publickey)` clone 失败 | 配置 GitHub SSH；确认是**协作者账号**的 key |
| CloseAI 代理下 clone GitHub 403 | 先 `openai_off` 再 `marketplace add` |
| `failed to parse ... description` | 运行 `fix_humanize_codex_hooks.sh` |
| `install.sh: ORIGINAL_ARGS unbound` | 改用 `install-skills-codex.sh --target codex` |
| bubblewrap 警告 | 可忽略，Codex 使用 bundled bubblewrap |
| RLCR 不触发 review | 检查 `~/.codex/hooks.json` 无 `description` 且 `[features] hooks = true` |
| qoder review 失败 | 确认 `qoderclicn` 可用且已登录；H 集群代理由插件脚本自动处理。若反复 `Not logged in` / hook 后凭据消失，见 **[codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md)**（HOME 错位、Authentik 403、`automatic_auth_rejection`） |

---

## 七、升级与维护

### Codex CLI

升级前先检查是否有活动 RLCR；暂停状态适合更新。固定版本更新并验证：

```bash
npm install -g @openai/codex@0.149.1
npm install -g --prefix /wangxuanxu/node/node-v22 @openai/codex@0.149.1

/root/node/node-v22/bin/codex --version
/wangxuanxu/node/node-v22/bin/codex --version
PATH="/root/node/node-v22/bin:$PATH" humanize24 doctor --project <root>
PATH="/wangxuanxu/node/node-v22/bin:$PATH" humanize24 doctor --project <root>
```

root 安装属于系统侧内容，更新后须提醒保存开发机镜像；个人 PVC 安装与回滚备份
不依赖系统镜像。恢复旧版时优先用 npm 安装明确旧版本；网络不可用时再从上述备份恢复。

### Humanize 插件

```bash
openai_off
codex plugin marketplace upgrade humanize-codex-qoder
bash ~/.codex/.tmp/marketplaces/humanize-codex-qoder/scripts/install-skills-codex.sh --target codex
bash ~/tricks-for-cluster/fix_humanize_codex_hooks.sh
```

### Humanize 代码回推约定（重要）

对本机 `~/.agents/skills/humanize` 的修改，**默认只推送到个人仓库**：

- 推送目标：[`Harold-Finchwxx/humanize-codex-qoder`](https://github.com/Harold-Finchwxx/humanize-codex-qoder)  
  (`git@github.com:Harold-Finchwxx/humanize-codex-qoder.git`)
- **不要**默认直推合作者师兄仓库 [`HaoyiZhu/humanize-codex-qoder`](https://github.com/HaoyiZhu/humanize-codex-qoder)
- 需要合入上游时：从个人 fork 开 PR，或与仓库维护者另行协商

安装 / marketplace 仍可继续跟踪上游 `HaoyiZhu/humanize-codex-qoder`（见上文安装步骤）。

---

## 相关文档

- **[codex_humanize_usage_zh.md](codex_humanize_usage_zh.md)** — **使用说明（中文）**：命令、RLCR 流程、配置、监控
- **[codex_qoder_auth_and_review_troubleshoot.md](codex_qoder_auth_and_review_troubleshoot.md)** — qoder 登录失败 / Stop hook 审查失败：原因、修复与成功判定
- **[codex_humanize_kubebrain_incident_log_2026-08.md](codex_humanize_kubebrain_incident_log_2026-08.md)** — 2026-08 问题与解决方案总表
- [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md) — Codex / CloseAI 代理、中文回复与输入
- [codex_domestic_models_setup.md](codex_domestic_models_setup.md) — `codex-cn` 国产模型
- 上游英文：`~/.codex/.tmp/marketplaces/humanize-codex-qoder/docs/usage.md`

## 方法论阶段（Codex+qoder，非 Claude Opus）

Claude 时代 Humanize 在退出前会要求 spawn **Opus** 做脱敏方法论分析。当前 **Codex + qoderclicn** 运行时通常无 Opus，会导致无意义的失败与回退。

本机技能已改为：使用**当前会话可用的 Codex 模型**完成该阶段；计划测验 / 合规检查也不再硬编码 `opus`/`sonnet`。不需要该阶段时加 `--privacy`。细节见 [codex_humanize_kubebrain_incident_log_2026-08.md](codex_humanize_kubebrain_incident_log_2026-08.md)。
