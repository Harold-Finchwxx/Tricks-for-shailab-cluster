# T 集群 OpenAI / Claude API 代理说明

## 背景

T 集群访问 GPT 相关资源时，**只开放常用的 Claude、GPT API 接口**，其他外网地址不开放。集群提供 **CloseAI 专用代理**，供 Codex CLI、Claude Code 等工具调用 OpenAI / Anthropic API。

这与日常浏览外网用的 **Authentik 通用代理**（`proxy_on` / `PROXY_URL`）是两套机制，用途不同，不要混用。

| 代理 | 地址（示例） | 用途 |
|------|----------------|------|
| **CloseAI（API 专用）** | `http://closeai-proxy.pjlab.org.cn:23128` | OpenAI / Claude API（`codex`、`claude`） |
| **Authentik（通用）** | `http://<user>:<token>@10.1.20.50:23128/` | 一般外网访问、`npm install`、HuggingFace 等 |

---

## 已在 shell 中的配置

以下配置已写入 **`~/.bashrc`** 与 **`~/.zshrc`**（二者内容一致）。

### 1. 代理地址

```bash
CLOSEAI_PROXY_ADDR="http://closeai-proxy.pjlab.org.cn:23128"
```

### 2. 开关函数（与集群文档一致）

```bash
openai_on() {
    export http_proxy="$CLOSEAI_PROXY_ADDR"
    export https_proxy="$CLOSEAI_PROXY_ADDR"
    export HTTP_PROXY="$CLOSEAI_PROXY_ADDR"
    export HTTPS_PROXY="$CLOSEAI_PROXY_ADDR"
    export PROXY_STATUS="OpenAI Proxy on"
    echo "$PROXY_STATUS"
}

openai_off() {
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    export PROXY_STATUS="OpenAI Proxy off"
    echo "$PROXY_STATUS"
}
```

### 3. Codex / Claude 自动代理

直接运行 `codex` 或 `claude` 时会**自动**调用 `openai_on`，无需每次手动开代理：

```bash
codex() {
    openai_on
    command codex "$@"
}

claude() {
    openai_on
    command claude "$@"
}
```

若需绕过包装、直接调用二进制，可使用：

```bash
command codex
command claude
```

### 4. humanize24 专用代理

`humanize24` 的监督器通过 Python 直接启动 Codex，不会经过上述 `codex()` shell
函数。因此必须单独导出：

```bash
export HUMANIZE24_CODEX_PROXY="$CLOSEAI_PROXY_ADDR"
```

启动器会仅在 Codex 子进程中用该值覆盖大小写 `HTTP(S)_PROXY` 和 `ALL_PROXY`；
不会把代理 URL 写入 launcher state。Humanize 的 qoderclicn Stop hook 仍按其独立
配置使用 Authentik 通用出口。

---

## 使用方法

### 方式 A：直接启动 CLI（推荐）

```bash
codex    # 自动启用 CloseAI 代理
claude   # 自动启用 CloseAI 代理
```

### 方式 B：手动开关

适用于测试代理、或在其它脚本里临时启用 API 代理：

```bash
openai_on
curl ipinfo.io
openai_off
```

### 方式 C：在计算节点上使用

若需在 **计算节点** 内调用 API，提交作业前确保环境已加载（例如 `source ~/.bashrc`），再运行 `codex` / `claude` 或手动 `openai_on`：

```bash
mysrun -c 4 bash -lc 'source ~/.bashrc && openai_on && codex --help'
```

**注意**：`npm install` 等下载依赖通常应使用 **`proxy_on`（Authentik）**，而不是 CloseAI 代理；CloseAI 仅面向 GPT / Claude API。

---

## 验证代理是否生效

启用 `openai_on` 后执行：

```bash
curl ipinfo.io
```

成功时应看到类似下面的 **美国** 出口信息（IP 可能变化，地区一般为 Los Angeles / California）：

```json
{
  "ip": "98.158.103.139",
  "city": "Los Angeles",
  "region": "California",
  "country": "US",
  "loc": "34.0522,-118.2437",
  "org": "AS41095 IPTP LTD",
  "postal": "90075",
  "timezone": "America/Los_Angeles",
  "readme": "https://ipinfo.io/missingauth"
}
```

也可检查环境变量：

```bash
echo $http_proxy
# 应输出: http://closeai-proxy.pjlab.org.cn:23128
```

---

## 前置依赖：Node.js 与 CLI 安装

CloseAI 代理只解决 **API 访问**；还需在本机 home 目录安装 Node.js 与全局 CLI。

### Node.js（用户目录）

```bash
# 从集群共享目录复制（路径以实际为准）
cp /mnt/inspurfs/eb3d_t/share/node-v22.9.0-linux-x64-glibc-217.tar.gz ~/

mkdir ~/node
tar -xzvf ~/node-v22.9.0-linux-x64-glibc-217.tar.gz -C ~/node/
mv ~/node/node-v22.9.0-linux-x64-glibc-217 ~/node/node-v22

# ~/.bashrc / ~/.zshrc 中已添加：
# export PATH=$HOME/node/node-v22/bin:$PATH
```

### 全局安装 CLI（建议在计算节点执行）

```bash
mysrun npm install -g @openai/codex
mysrun npm install -g @anthropic-ai/claude-code
```

安装完成后验证：

```bash
npm list -g --depth=0
command -v codex claude
codex --version
claude --version
```

---

## 常见问题

### 1. `source ~/.bashrc` 报 `LOG2SYSLOG_FIRST_RUN: readonly variable`

在**已登录的 bash 会话**里重复 `source ~/.bashrc` 时，集群审计脚本可能触发该警告，一般可忽略；PATH 与代理函数通常仍会生效。新开终端即可避免。

### 2. 在 bash 里执行 `source ~/.zshrc`

`.zshrc` 含 zsh 专用语法（`autoload`、`compinit` 等），**不要在 bash 中 source**；bash 用 `source ~/.bashrc`，zsh 用 `source ~/.zshrc`。

### 3. API 仍连不上

按顺序排查：

1. 是否已 `openai_on` 或通过 `codex` / `claude` 包装启动；
2. `curl ipinfo.io` 是否显示美国 IP；
3. 是否误用了 `proxy_on`（Authentik）而非 CloseAI；
4. API Key / ChatGPT 登录是否已在 CLI 内完成（与代理无关，但无凭证同样无法调用）。

若只有 `humanize24` 失败，还需运行：

```bash
echo "$HUMANIZE24_CODEX_PROXY"
humanize24 doctor --project /path/to/project
```

`doctor` 的 `codex-proxy` 应显示 CloseAI 的脱敏 endpoint；若显示
`not configured`，说明当前 shell 尚未加载新配置。

### 4. 与 `proxy_on` / `proxy_off` 的关系

- **`openai_on`**：仅设置 CloseAI 四个代理变量，**不**设置 `no_proxy`。
- **`proxy_on`**：Authentik 代理 + 内网 `NO_PROXY_LIST`，适合 wandb、pip、npm 等。
- 二者会互相覆盖 `http_proxy` / `https_proxy`；用完一种场景后可 `openai_off` 或 `proxy_off` 再切换。

---

## Codex 默认中文回复

已在 **`~/.codex/`** 配置：Codex 面向用户的回复默认使用**简体中文**（`codex` 与 `codex-cn` 均生效）。修改后需**新开 Codex 会话**。

### 已写入的配置

**1. `~/.codex/AGENTS.md`**（全局，Codex 官方推荐）

```markdown
# 全局偏好

- 始终用**简体中文**回复用户，除非用户明确要求使用其他语言。
- 代码、标识符、commit message、文件内容按项目惯例（通常为英文）；仅在用户要求时对代码或注释使用中文。
```

**2. `~/.codex/config.toml`**

```toml
developer_instructions = "Always respond to the user in Simplified Chinese (简体中文), unless the user explicitly requests another language."
```

`AGENTS.md` 与 `developer_instructions` 叠加生效；后者在 AGENTS.md 之后追加。

### 按项目覆盖

若某个仓库需要英文回复，可在该仓库根目录放置 `AGENTS.md` 或 `AGENTS.override.md`，写项目级语言偏好（Codex 从 cwd 向上合并，**更近目录优先**）。

### 临时改用其他语言

- 在 TUI 中直接说明，例如：「这次请用英文回复」
- 单次启动覆盖：

```bash
codex -c 'developer_instructions="Respond in English for this session."'
```

### 说明

国产模型 catalog 中的系统指令为英文，不影响上述「用户可见回复用中文」的偏好；代码与 commit 仍建议按项目惯例使用英文。

### qoderclicn 默认简体中文（Humanize review）

Humanize 的 review 端走 **qoderclicn**，需单独配置（与 Codex 的 `AGENTS.md` 无关）：

```bash
bash ~/tricks-for-cluster/setup_qoderclicn_zh.sh
```

- 在 `~/.local/bin/qoderclicn` 安装 wrapper，自动 `--append-system-prompt` 中文偏好
- 写入 `~/.config/humanize/config.json` 的 `qoder_append_system`
- 自定义：`export QODERCLICN_APPEND_SYSTEM_PROMPT="..."`

详见 [codex_humanize_usage_zh.md](codex_humanize_usage_zh.md)。

---

## SSH / Cursor 终端无法输入中文（IME）

与上一节「**中文回复**」不同：本节解决的是**你在终端里用拼音/输入法打不出中文**的问题。

### 现象

- 在 Cursor 集成终端 SSH 到集群后，切换到中文输入法，**bash 或 Codex TUI 输入框里敲拼音无反应或无法上屏**
- **Cursor 聊天框能打中文**，同一窗口的远端终端却不能（粘贴中文通常仍可用）
- 有时仅 **Codex 第二轮对话后** IME 才异常（Codex TUI 已知 bug）

### 已验证（2026-08-19，Windows + Cursor Remote SSH）

**只把本机输入法从搜狗拼音换成微软拼音，远端终端即可直接打中文**；未改 Cursor 设置、未在集群装输入法。

| 位置 | 搜狗拼音 | 微软拼音 |
|------|----------|----------|
| Cursor 聊天框 | 正常 | 正常 |
| Cursor 远端集成终端（bash / Codex TUI） | 拼音不上屏，或打成英文字母 | 可直接组字上屏 |
| 终端里粘贴中文 | 可用 | 可用 |

聊天框是普通文本框，Chromium 对残缺 IME 事件有兜底；集成终端是 xterm.js，几乎只认标准组字事件：

`compositionstart` → `compositionupdate` → `compositionend`

微软拼音走系统 TSF，会发齐这些事件。搜狗常只发 `keyup`、跳过 `compositionend`，并把拼音键当普通按键送进 PTY；另外搜狗有应用白名单（如 `chrome.exe` / `Code.exe`），**`Cursor.exe` 通常不在名单里**。不要在无桌面的集群节点上装 fcitx/ibus，拦不到本机按键。

### 原因（不是 Codex 配置错误）

```text
本机输入法 (IME)  →  Cursor/VS Code 集成终端 (xterm.js)  →  SSH  →  集群 bash / codex
                         ↑ 此处 IME 支持差（已知 issue）
集群节点无 fcitx/ibus，无法在服务器侧安装中文输入法
```

| 层级 | 说明 |
|------|------|
| 集群 | locale 已是 UTF-8（如 `C.UTF-8` / `en_US.UTF-8`），**显示**中文正常；**不负责**提供输入法 |
| SSH | 字符由本机 IME 经 SSH 客户端送入，编码需 UTF-8 |
| Cursor 终端 | xterm.js 对部分 IME（搜狗/百度）兼容性差；微软拼音 / Rime 通常可用；粘贴 UTF-8 一般可用 |
| Codex TUI | 全屏 TUI + IME 组合输入更易出问题；`disable_paste_burst` 可减轻粘贴被吞 |

### 自测

```bash
read -r -p "粘贴「测试」后回车: " line; echo "收到: $line"
```

| 结果 | 含义 |
|------|------|
| 粘贴 `测试` 显示正常 | 编码 OK，问题在 IME → 用下方 workaround |
| 粘贴也乱码 | 检查 Cursor / SSH 客户端字符集为 UTF-8 |

### 推荐做法（按优先级）

**1. Windows：用微软拼音（或 Rime），不要用搜狗/百度（首选）**

Cursor 远端终端里，这是改动最小、也已验证有效的做法。不必改 `settings.json`、不必在集群装输入法。仍想用搜狗时，可试「系统候选框 / 兼容模式」，但不稳。

**2. 粘贴（交互 TUI 仍可用）**

本地编辑器或聊天框写好中文 → 终端 / Codex 输入框 **`Ctrl+Shift+V`**（Mac 可试 `Cmd+V`）。

**3. `codex-cn-ask` / `codex-ask`（已写入 `~/.bashrc` / `~/.zshrc`）**

绕开 TUI 输入框，用非交互 `exec` 发送中文 prompt：

```bash
source ~/.bashrc

# 国产模型（deepseek / codex-cn 同款代理与桥接）
codex-cn-ask "请帮我 review 这个模块的设计"
codex-cn-ask -f ~/prompt.txt

# 从 stdin
echo "列出 refactor 步骤" | codex-cn-ask

# GPT + CloseAI
codex-ask "解释这段代码"
codex-ask -f ~/prompt.txt
```

**4. 换终端或其它兜底**

| 尝试 | 说明 |
|------|------|
| **Windows Terminal / iTerm** 直连 SSH | 外置终端的 IME 往往优于 Cursor 集成终端 |
| Codex 升级 | `codex update`（旧版 TUI IME bug 较多） |
| 失焦再聚焦 | 切到其他窗口再点回终端（Windows 上偶有效） |
| `terminal.integrated.gpuAcceleration: "off"` | 可选；微软拼音已够用时不必改 |

**5. Cursor 设置（可选）**

用户 `settings.json` 关闭远程终端 local echo，减轻高延迟下字符错乱：

```json
"terminal.integrated.localEchoLatencyThreshold": -1
```

### 已写入的本机配置

| 文件 | 内容 |
|------|------|
| `~/.bashrc` / `~/.zshrc` | `codex-cn-ask`、`codex-ask` 函数 |
| `~/.codex/config.toml` | `disable_paste_burst = true` |

修改 `config.toml` 或 shell 函数后：Codex 需**新开会话**；shell 函数需 `source ~/.bashrc`。

### 与「中文回复」的关系

| 配置 | 作用 |
|------|------|
| `~/.codex/AGENTS.md` + `developer_instructions` | Codex **输出**用简体中文 |
| 本机微软拼音（Cursor 终端）/ 粘贴 / `codex-cn-ask` | 你**输入**中文 prompt |

二者独立：即使输入用英文，Codex 仍会中文回复。Cursor 远端终端优先换微软拼音；粘贴与 `codex-cn-ask` 仍可作为兜底。

---

## 参考

- 集群文档：T 集群 OpenAI / Claude 代理（CloseAI）
- 本机配置：`~/.bashrc`、`~/.zshrc` 中「T集群 OpenAI / Claude API 专用代理」段落
