# Codex CLI 接入国产模型（DeepSeek / Qwen / GLM / Kimi）

在 T 集群上，Codex 默认走 **OpenAI + CloseAI**；国产模型统一走 **Authentik 出站代理（`proxy_on`）+ 本地 Responses 桥接**。

## 架构

```text
codex-cn  →  127.0.0.1:8786 (统一网关)  →  按 model 路由  →  127.0.0.1:878x 桥接  →  官方 Chat Completions API
     ↑              ↑                              ↑
 Codex CLI    domestic_models_gateway         deepseek-responses-proxy
                                                    ↑
                                              PROXY_URL (Authentik)
```

在 TUI 内输入 **`/model`** 即可在同一会话中切换 DeepSeek / Qwen / GLM / Kimi，无需多个启动命令。

| Provider | 本地端口 | 上游 API | 环境变量 | 模型 slug 示例 |
|----------|----------|----------|----------|----------------|
| DeepSeek | 8787 | `https://api.deepseek.com` | `DEEPSEEK_API_KEY` | `deepseek-v4-flash`, `deepseek-v4-pro` |
| Qwen | 8788 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `DASHSCOPE_API_KEY` | `qwen3-coder-plus`, `qwen-coder-turbo` |
| GLM | 8789 | `https://open.bigmodel.cn/api/paas/v4` | `ZHIPUAI_API_KEY` | `glm-4-flash`, `glm-4-plus` |
| Kimi | 8790 | `https://api.moonshot.cn/v1` | `MOONSHOT_API_KEY` | `kimi-k2.7-code` |

统一网关端口：**8786**（`domestic_models_gateway.py`）。模型路由表：`tricks-for-cluster/domestic_model_routes.conf`。

配置文件：`tricks-for-cluster/domestic_models.conf`（增删 provider 改此文件）。

---

## 一、安装桥接工具（一次性）

```bash
proxy_on
git clone --depth 1 https://github.com/holo-q/deepseek-responses-proxy.git /tmp/deepseek-responses-proxy
pip3 install --user --ignore-requires-python /tmp/deepseek-responses-proxy
```

---

## 二、配置 API Key

```bash
cp ~/.domestic_models_env.example ~/.domestic_models_env
# 编辑 ~/.domestic_models_env，填入你要用的平台 Key（不必全填）
source ~/.bashrc
```

| 平台 | 控制台 | 环境变量 |
|------|--------|----------|
| DeepSeek | https://platform.deepseek.com/ | `DEEPSEEK_API_KEY` |
| Qwen 百炼 | https://bailian.console.aliyun.com/ | `DASHSCOPE_API_KEY` |
| 智谱 GLM | https://open.bigmodel.cn/ | `ZHIPUAI_API_KEY` |
| Kimi | https://platform.moonshot.cn/ | `MOONSHOT_API_KEY` |

旧文件 `~/.deepseek_env` 仍兼容；建议迁移到 `~/.domestic_models_env`。

---

## 三、启动桥接

```bash
# 启动所有已配置 Key 的 provider + 统一网关 (8786)
bash ~/tricks-for-cluster/start_domestic_proxies.sh

# 或只启动某一个（不启动网关，适合旧版单 provider profile）
bash ~/tricks-for-cluster/start_domestic_proxies.sh qwen

# 单独重启网关（需各 provider 桥接已在运行）
bash ~/tricks-for-cluster/start_domestic_gateway.sh
```

日志：`~/.codex/proxy-logs/<provider>.log`、`domestic-gateway.log`

---

## 四、使用 Codex

| 命令 | 说明 |
|------|------|
| `codex` | GPT-5.5（CloseAI） |
| **`codex-cn`** | 国产模型统一入口；启动后在 TUI 输入 **`/model`** 切换模型 |

`codex-cn` 等价于 `codex --profile domestic`，默认模型为 `deepseek-v4-flash`。可选模型见 `~/.codex/domestic-models-catalog.json`。

运行 `codex-cn` 时会自动：`proxy_on` 出站 + 启动全部已配置 Key 的桥接 + 统一网关。

### 中文 prompt（Cursor SSH 终端打不出字时）

Cursor 集成终端经 SSH 使用中文 IME 常失效（与模型无关）。推荐：

```bash
# 非交互，直接发中文（等同 codex-cn + exec）
codex-cn-ask "你的中文问题"
codex-cn-ask -f prompt.txt
```

交互 TUI 内可 **粘贴** 中文（`Ctrl+Shift+V`）。完整说明见 [openai_claude_proxy_notes.md — SSH / Cursor 终端无法输入中文](openai_claude_proxy_notes.md#ssh--cursor-终端无法输入中文ime)。

Codex **回复**默认简体中文（`~/.codex/AGENTS.md`），见同文档「Codex 默认中文回复」一节。

---

## 五、Coding Plan / 订阅 vs API

| 类型 | 说明 | Codex 接入方式 |
|------|------|----------------|
| **按量 API** | 各平台控制台创建 API Key | 填入 `~/.domestic_models_env`，按本文配置即可 |
| **Coding Plan 订阅** | 如 Kimi Code 月付、`kimi-for-coding` 等 | 若平台提供 **OpenAI 兼容 API Key + base_url**，填入对应 env 并改 `domestic_models.conf` 上游地址；若仅支持 Claude Code 专用 env（如 `ANTHROPIC_BASE_URL`），请用 **Claude Code** 而非 Codex |
| **聚合网关** | OpenRouter、AIHubMix 等一家 Key 多模型 | 在 `domestic_models.conf` 增加一行，指向上游 `base_url`，`env_key` 填网关 Key |

---

## 六、新增模型

1. 在 `~/.codex/domestic-models-catalog.json` 增加模型 slug。
2. 在 `tricks-for-cluster/domestic_model_routes.conf` 增加一行：`模型slug|provider_id`（provider 须已在 `domestic_models.conf` 中定义）。
3. 重启桥接与网关：`bash ~/tricks-for-cluster/start_domestic_proxies.sh`

使用 `codex-cn` 时无需为每个模型单独建 profile；TUI 内 `/model` 会从 catalog 列出全部模型。

---

## 七、常见问题

| 现象 | 处理 |
|------|------|
| 终端 / TUI 无法输入中文 | Cursor SSH + IME 限制；用 **`codex-cn-ask`** 或粘贴；见 [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md#ssh--cursor-终端无法输入中文ime) |
| 长时间 Working | 检查 `proxy-logs/*.log` 是否 timeout；确认 `proxy_on` 出站可用 |
| 401 invalid key | 检查对应 `*_API_KEY` 是否正确；改 Key 后重启桥接 |
| 404 | 模型 ID 错误或 upstream base_url 不对 |
| 仅 DeepSeek 可用 | 其他 Key 未填会被 `start_domestic_proxies.sh` 跳过 |

---

## 相关文档

- [codex_deepseek_setup.md](codex_deepseek_setup.md) — DeepSeek 专项说明（已并入本文）
- [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md) — OpenAI / Claude CloseAI 代理、**Codex 中文回复与中文输入（IME）**
