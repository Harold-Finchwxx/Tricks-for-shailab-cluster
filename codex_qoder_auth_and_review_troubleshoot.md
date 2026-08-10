# Codex 调用 qoderclicn：登录失败原因与成功调用流程

记录 2026-08 在 **Kubebrain / 远程开发机**（`HOME` 可能指向 PVC、出站走 Authentik）上跑 **Humanize RLCR** 时，Codex Stop hook 调 `qoderclicn` **登录失败 / 审查失败** 的根因、排查与已落地解决方案。配套：

- 安装：[codex_humanize_setup.md](codex_humanize_setup.md)
- 用法：[codex_humanize_usage_zh.md](codex_humanize_usage_zh.md)
- Wrapper 安装：`setup_qoderclicn_zh.sh`

**环境约定（本机实验）**

| 项 | 路径 / 值 |
|----|-----------|
| 工具与认证（镜像侧） | `/root`：`/root/.qoder-cn`、`/root/.local/bin/qoderclicn`、`/root/.agents/skills/humanize` |
| 个人数据 PVC | `/wangxuanxu`（可含旧 `.qoder-cn` 作备份） |
| 出站代理 | `PROXY_URL` → Authentik（如 `http://10.1.20.50:23128`） |
| Smoke 仓库 | `/wangxuanxu/humanize-smoke-test`（**必须是独立 git repo**） |

---

## 1. 调用链（成功时应该怎样）

```text
humanize-rlcr / 会话内继续实现
        │
        ▼
Codex 本轮结束（写 round-N-summary.md）
        │
        ▼
~/.codex/hooks.json  →  Stop → loop-codex-stop-hook.sh
        │
        ├─ pin HOME=/root、PATH 含 /root/.local/bin
        ├─ 注入 Authentik PROXY_URL / HTTP(S)_PROXY / ALL_PROXY
        └─ ask-qoder.sh → qoderclicn（wrapper）
                │
                ├─ 再强制 HOME=/root + 代理
                ├─ 若 .auth/user 缺失则从 backup/PVC 回填
                └─ 真实二进制无头 review（约数十秒～数分钟）
                        │
                        ▼
        round-N-review-result.md（COMPLETE / [P0]–[P9] / PASS）
        state.md 推进（review_started / finalize …）
```

**成功判定（不要只看交互式 TUI）**

1. `HOME=/root qoderclicn status` 有 **Username**（不是 `Not logged in`）。
2. 缓存目录 `~/.cache/humanize/<sanitized-project>/qoder-<ts>-*`：
   - `exit_code=0`
   - **duration ≫ 2s**（真正推理常见 30–100s+）
   - 结果不是 `Not logged in · Please run /login`
3. 项目 `.humanize/rlcr/<session>/` 出现：
   - `round-*-review-result.md`（独立复审含 `COMPLETE`；代码审查无 findings 或带 `[Pn]`）
   - `review_started: true`（或 `complete-state.md` / `finalize-summary.md`）
4. `/root/.qoder-cn/logs/runs/<run>/qodercli.log` 有 `Headless session completed successfully`，**没有**紧跟着的 `credential.clear reason=automatic_auth_rejection`。

Smoke 实测（登录修复后）：Round 0 独立复审 COMPLETE；Round 1/2 diff review PASS；**产品代码未因 review 改动**（无 findings）。早期 2s 失败均为鉴权/403。

---

## 2. 失败现象（Codex / Stop hook 侧）

Stop hook 反馈典型形态：

```text
# Qoder Review Failed
qodercli exited with code 1
...
result: "Not logged in · Please run /login"
```

或交互里 `qoderclicn status` → `Account: Not logged in`，同时 Codex 发起 `qoderclicn login` 等浏览器 device flow（约 5 分钟超时）。

**注意**：表面上像「没登录」，底层经常是 **调用时拿不到有效用户信息（含网关 403）→ CLI 自动清凭据**，下一次就变成真正的 Not logged in。

---

## 3. 根因分析（按出现频率）

### 3.1 双 HOME / 双认证目录（最易踩坑）

| Store | 典型路径 | 说明 |
|-------|----------|------|
| 镜像 / root | `/root/.qoder-cn/.auth/user` | **Stop hook / wrapper 应使用的店** |
| PVC | `/wangxuanxu/.qoder-cn/.auth/user` | 旧机或 `HOME=/wangxuanxu` 时写入；可作备份 |

Codex / Cursor 会话常把 `HOME` 设成工作区 PVC。若 hook 或二进制未 pin `HOME=/root`：

- 读到 PVC 上过期或另一账号凭据 → `getUserInfo` **403**；
- 或以为「已登录」其实看的是另一份 store。

**日志特征**（`/root/.qoder-cn/logs/runs/.../qodercli.log`）：

```text
auth.getUserInfo → HTTP 403
credential.clear reason=automatic_auth_rejection
credential.load outcome=missing
```

之后 `/root/.qoder-cn/.auth/user` 被删掉。

### 3.2 Stop hook 环境代理不完整

- 交互式 shell 有 `proxy_on` / `PROXY_URL`，**hook 子进程不一定继承**。
- 或继承了被剥离 / 无效的 `HTTP_PROXY`，Authentik 对 `gateway.qoder.com.cn` / `openapi.qoder.com.cn` 返回 **403**。
- CLI 把这类 403 当成鉴权失败 → **同上，自动 wipe `.auth/user`**。

沙箱外 `curl` 到 userinfo 得到 **401**（服务可达、只是未带 token）≠ hook 内 **403**（代理/鉴权链路拒绝）。

### 3.3 浏览器登录与「假恢复」

- Device login 链接约 **5 分钟**有效；未在网页确认 → `Device flow timed out`。
- 仅从 PVC 拷回 `user` 后立刻再触发失败的 hook → token 再次被 `automatic_auth_rejection` 删掉，表现为「刚恢复又没了」。
- 悬挂的 `qoderclicn login` 与已恢复的 status 并存时，会误导排障；auth 已好时应结束 login，而不是一直等浏览器。

### 3.4 其它（次要）

- PATH 指向 PVC 旧 `qoderclicn` / 坏掉的 symlink（硬编码 `/mnt/hwfile/...`）。
- Humanize 项目不在 **git repo** 根（例如在 `/wangxuanxu` 根开 RLCR）→ 状态/hook 解析异常。
- 插件 hooks 未装、`[features] hooks` 未开 → Stop 根本不调 qoder（表现是「没有 review」，不是 Not logged in）。

---

## 4. 已落地解决方案

### 4.1 Wrapper：`/root/.local/bin/qoderclicn`

由 `setup_qoderclicn_zh.sh` 安装/维护，关键逻辑应包含：

1. **root 强制 `HOME=/root`**，认证只走 `/root/.qoder-cn`。
2. **始终注入** `PROXY_URL`（环境变量或 `/root/.bashrc`），并设置 `HTTP(S)_PROXY` / `ALL_PROXY`（不要只在「当前为空」时注入一次）。
3. **wipe 后自动回填**：`/root/.qoder-cn/.auth-backup/user`（推荐 `400`）或 PVC `/wangxuanxu/.qoder-cn/.auth/user`。
4. 成功调用后刷新 local/PVC backup，避免下次永久丢登录。
5. 默认 `--append-system-prompt` 简体中文（与 Humanize 对齐）。

环境变量覆盖（可选）：

| 变量 | 含义 |
|------|------|
| `QODER_AUTH_LOCAL_BACKUP` | 本地 backup 路径（默认 `/root/.qoder-cn/.auth-backup/user`） |
| `QODER_AUTH_PVC_BACKUP` | PVC mirror（默认 `/wangxuanxu/.qoder-cn/.auth/user`） |
| `HUMANIZE_QODER_PROXY_URL` / `PROXY_URL` | Authentik 出站 |

### 4.2 Humanize Stop / ask-qoder

- `hooks/loop-codex-stop-hook.sh`：pin `HOME=/root`、PATH、**强制** Authentik 代理。
- `scripts/lib/qoder-cli.sh`：`humanize_qoder_ensure_root_home`；proxy mode 支持 `auto|always|never|inherit`；显式 `PROXY_URL` 优先于 H 集群 headless 默认。
- `~/.codex/hooks.json` 指向 `/root/.agents/skills/humanize/hooks/loop-codex-stop-hook.sh`。

升级 Humanize 插件后若 hook 被上游覆盖，需重新合并上述 pin/proxy 逻辑，并跑 `fix_humanize_codex_hooks.sh`。

### 4.3 手工恢复凭据（紧急）

**不要**在未修好代理的情况下反复触发 Stop（会再次 wipe）。

```bash
# 1) 确认代理
echo "${PROXY_URL:-}"; grep -E '^(export[[:space:]]+)?PROXY_URL=' /root/.bashrc | head -1

# 2) 从 PVC 回填（勿 cat 打印 token）
mkdir -p /root/.qoder-cn/.auth /root/.qoder-cn/.auth-backup
cp -f /wangxuanxu/.qoder-cn/.auth/user /root/.qoder-cn/.auth/user
chmod 600 /root/.qoder-cn/.auth/user
cp -f /root/.qoder-cn/.auth/user /root/.qoder-cn/.auth-backup/user
chmod 400 /root/.qoder-cn/.auth-backup/user

# 3) 验证（必须 HOME=/root）
HOME=/root PATH=/root/.local/bin:$PATH qoderclicn status
# 期望：Username: <你的账号>

# 4) 可选连通性（代理下）
HOME=/root PATH=/root/.local/bin:$PATH qoderclicn --list-models >/dev/null && echo OK
```

浏览器登录（backup 都没有时）：

```bash
HOME=/root PATH=/root/.local/bin:$PATH qoderclicn login
# 在时限内打开终端给出的 qoder.cn/device 链接并确认
# 成功后再执行上面的 backup 拷贝
```

auth 已恢复时：**取消悬挂的 login**，不要并行再开一个 device flow。

---

## 5. 推荐操作流程（排障 Checklist）

```text
① Stop 报 Qoder Review Failed / Not logged in
        │
        ▼
② HOME=/root qoderclicn status
        ├─ 已登录 → 查最近 qodercli.log 是否 403 + credential.clear
        │            → 修代理（§4.1–4.2），必要时恢复 backup（§4.3）
        └─ 未登录 → §4.3 恢复或 login → 写 backup
        │
        ▼
③ 确认 hook 用的是 /root/.local/bin/qoderclicn（which / PATH）
        │
        ▼
④ 再让 Codex 正常结束一轮，触发 Stop（不要手改 review_started）
        │
        ▼
⑤ 看 ~/.cache/humanize/.../qoder-* 与 round-*-review-result.md
        ├─ duration~2s + Not logged in → 仍是鉴权/403，回到 ②
        └─ duration 数十秒+ + COMPLETE/PASS → 成功
```

**不要做的事**

- 手改 `.humanize/rlcr/*/state.md` 伪造 `review_started`（绕过门禁，状态易不一致）。
- 在 hook 仍会 403 时循环「恢复 → 立刻再 Stop」。
- 把含 challenge 的 login URL 转发他人。
- 依赖 PVC PATH 上的旧 qoder 二进制。

---

## 6. 日志与证据路径

| 用途 | 路径 |
|------|------|
| RLCR 状态 / 审查结果 | `<repo>/.humanize/rlcr/<ts>/`（`state.md`、`round-*-review-result.md`、`finalize-summary.md`） |
| ask-qoder 缓存 | `~/.cache/humanize/<sanitized-cwd>/qoder-<ts>-*` |
| Stop/Codex 调试 | 同上父目录下 `round-*-codex-*.{cmd,out,log}` |
| qoder CLI 运行日志 | `/root/.qoder-cn/logs/runs/<run-id>/qodercli.log` |
| 认证文件（勿打印内容） | `/root/.qoder-cn/.auth/user`、`.auth-backup/user`、PVC mirror |

---

## 7. 与成功 Smoke 的对照结论

| 问题 | 结论 |
|------|------|
| qoder 是否被成功调用做独立复审？ | **是**（COMPLETE，长时推理） |
| qoder 是否进入代码审查阶段？ | **是**（Round 1/2 PASS） |
| qoder 反馈是否导致改产品代码？ | **否**（无 `[Pn]` findings；finalize `NO_CHANGES`） |
| 早期失败主因 | HOME 错位 + 代理不完整 → gateway **403** → **automatic_auth_rejection** 清凭据 → 表现为 Not logged in |

---

## 8. 维护提示

- 改 `/root/.bashrc` 的 `PROXY_URL` 后，确认 wrapper / hook 仍能读到（或 export `HUMANIZE_QODER_PROXY_URL`）。
- 镜像保存实验：工具与 `/root/.qoder-cn` 配置放镜像侧；PVC 仅作数据与 auth mirror。
- Humanize / qoderclicn 升级后复查：`setup_qoderclicn_zh.sh`、`qoder-cli.sh`、Stop hook 的 HOME/proxy/backup 逻辑是否还在。
- 本文件应同时存在于 **`/root/tricks-for-cluster/`** 与 **`/wangxuanxu/tricks-for-cluster/`**；修改后请两边同步。
