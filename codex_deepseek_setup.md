# Codex CLI 接入 DeepSeek 官方 API

## 背景

当前 **Codex CLI（v0.142+）** 的自定义 provider 只支持 **OpenAI Responses API**（`wire_api = "responses"`）。

DeepSeek 官方 API 提供的是 **OpenAI Chat Completions** 接口（`https://api.deepseek.com/chat/completions`），**不能**在 `~/.codex/config.toml` 里直接把 `base_url` 指到 `https://api.deepseek.com` 就指望能用——通常会 **404** 或协议解析失败。

正确链路：

```text
Codex CLI  --Responses API-->  本地桥接代理 (127.0.0.1:8787)
                                      |
                                      v
                              DeepSeek 官方 API (Chat Completions)
```

桥接工具：[deepseek-responses-proxy](https://github.com/holo-q/deepseek-responses-proxy)（将 Responses 请求翻译成 Chat Completions）。

---

## 集群出站网络（Authentik 代理）

集群登录/计算节点通常**无法直连** `api.deepseek.com`。DeepSeek 桥接进程启动时会自动加载 `~/.bashrc` 中的 **`PROXY_URL`（与 `proxy_on` 相同）**，作为访问 DeepSeek 官方 API 的出站代理：

```bash
# 与 proxy_on 等价，已在 start_deepseek_proxy.sh 内自动设置
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export no_proxy="$NO_PROXY_LIST"
```

运行 `codex-cn`（或 `codex --profile domestic`）时也会自动启用上述代理并启动全部桥接与统一网关。

验证出站是否通（应返回 401，说明网络可达、仅缺 API Key）：

```bash
proxy_on
python3 -c "import urllib.request; print(urllib.request.urlopen('https://api.deepseek.com/', timeout=30).status)"
```

---

## 一、安装桥接代理

### 1. 克隆并安装（集群需开 `proxy_on` 访问 GitHub）

```bash
proxy_on
git clone --depth 1 https://github.com/holo-q/deepseek-responses-proxy.git /tmp/deepseek-responses-proxy
pip3 install --user --ignore-requires-python /tmp/deepseek-responses-proxy
```

安装后二进制在 `~/.local/bin/deepseek-responses-proxy`。

> 官方要求 Python ≥3.11；集群默认 base 为 3.9 时可用 `--ignore-requires-python` 安装，实测可运行。若异常，可在 conda 环境中用 3.11+ 安装。

### 2. 配置 DeepSeek API Key

```bash
cp ~/.deepseek_env.example ~/.deepseek_env
# 编辑 ~/.deepseek_env，填入 DeepSeek 平台 API Key：
# export DEEPSEEK_API_KEY="sk-..."
```

`~/.bashrc` / `~/.zshrc` 会自动 `source ~/.deepseek_env`。

---

## 二、Codex 配置（已写入本机）

### 用户级 `~/.codex/config.toml`

保留默认 OpenAI（`gpt-5.5`），并注册 DeepSeek provider：

```toml
model_catalog_json = "/mnt/petrelfs/wangxuanxu/.codex/deepseek-model-catalog.json"

[model_providers.deepseek]
name = "DeepSeek"
base_url = "http://127.0.0.1:8787/v1"
experimental_bearer_token = "codex-deepseek-local"
wire_api = "responses"
```

### Profile 文件（Codex 0.134+ 推荐方式）

| 文件 | 模型 |
|------|------|
| `~/.codex/deepseek-v4-flash.config.toml` | `deepseek-v4-flash`（快、便宜） |
| `~/.codex/deepseek-v4-pro.config.toml` | `deepseek-v4-pro`（更强） |

**不要**只用 `codex -m deepseek-v4-flash`——那样仍走 OpenAI 默认 provider。必须用 **`--profile`**。

---

## 三、日常使用

### 1. 启动本地桥接（或交给 shell 包装自动启动）

```bash
bash ~/tricks-for-cluster/start_deepseek_proxy.sh
```

### 2. 启动 Codex（DeepSeek）

```bash
# 快捷别名（已在 ~/.bashrc 配置）
codex-cn          # 统一入口，TUI 内 /model 切换 deepseek-v4-flash / deepseek-v4-pro / ...

# 或显式指定 profile
codex --profile deepseek-v4-flash
codex --profile deepseek-v4-pro
```

运行 DeepSeek profile 时会 **关闭 CloseAI 代理**（DeepSeek 是国内 API，无需走 CloseAI）；默认 `codex`（GPT）仍会 **自动 `openai_on`**。

### 3. 默认 OpenAI Codex（不变）

```bash
codex    # 仍使用 gpt-5.5 + CloseAI 代理
```

---

## 四、验证

```bash
# 1. 代理 health
curl http://127.0.0.1:8787/health

# 2. 非交互测试（需已配置 DEEPSEEK_API_KEY）
codex --profile deepseek-v4-flash exec "用一句话介绍你自己"
```

日志：`~/.codex/deepseek-proxy.log`

---

## 五、常见问题

| 现象 | 原因 / 处理 |
|------|-------------|
| `404` 连 DeepSeek | 未走本地代理，或 `base_url` 直接指到了 `api.deepseek.com` |
| `ETIMEDOUT` / 长时间 Working | 桥接未带出站代理；执行 `bash ~/tricks-for-cluster/start_deepseek_proxy.sh` 重启（已自动使用 `PROXY_URL`） |
| `未设置 DEEPSEEK_API_KEY` | 创建并填写 `~/.deepseek_env` |
| Model metadata not found 警告 | 已通过 `deepseek-model-catalog.json` 缓解；可忽略轻微性能提示 |
| DeepSeek 与 CloseAI 混用 | DeepSeek 用 `codex-cn`；OpenAI 用 `codex`；二者代理策略已在 shell 包装中区分 |

---

## 六、扩展其他国产模型

已统一集成，见 **[codex_domestic_models_setup.md](codex_domestic_models_setup.md)**。

---

## 相关文档

- [openai_claude_proxy_notes.md](openai_claude_proxy_notes.md) — CloseAI 代理（OpenAI / Claude API）
- [DeepSeek 官方 API 文档](https://api-docs.deepseek.com/)
- [Codex 高级配置（Custom model providers）](https://developers.openai.com/codex/config-advanced)
