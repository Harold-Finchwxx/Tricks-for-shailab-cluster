# 集群环境下安装与登录 wandb 经验总结

## 背景说明

本次问题的核心原因是：**受集群软件环境限制，无法直接安装完整的最新版 wandb**。  
在该环境中，直接升级到最新版时会触发源码构建（包括 Rust/Go 相关构建步骤），进而受到集群已有工具链版本与网络条件影响，导致安装失败或不稳定。

因此采用了“可落地”的安装策略：优先在当前环境中完成可用版本安装，再在官方源下验证并升级到可用的新版本。

---

## 关键现象与原因

1. 直接 `pip install -U wandb` 时，可能拉到 `tar.gz` 源码包并触发本地构建。
2. 构建过程中会依赖 `cargo` 等工具链；若集群系统版本较旧，可能无法兼容新版 lockfile/构建流程。
3. 网络波动或代理异常会造成大包下载中断，进一步放大安装失败概率。

---

## 实际可行的安装方法（推荐流程）

> 以下示例以 `vrae` 环境为例，请按需替换环境名。

### 1) 激活环境并检查版本

```bash
source /mnt/hwfile/wangxuanxu/miniconda3/etc/profile.d/conda.sh
conda activate vrae
python -m pip show wandb
```

### 2) 避免 `gpu_stats` 构建阻塞

```bash
export WANDB_BUILD_SKIP_GPU_STATS=true
```

### 3) 使用官方源安装目标版本（示例为 0.25.1）

```bash
python -m pip install "wandb==0.25.1" \
  --index-url https://pypi.org/simple \
  --timeout 120 --retries 20 --resume-retries 50
```

### 4) 验证安装结果

```bash
python -m pip show wandb
python -c "import wandb; print(wandb.__version__)"
```

---

## 关于 API Key 的重要说明

**这是本次升级最关键的业务原因：**

- 新版的 **86 位 wandb API Key** 需要使用新版 wandb 才能正常登录；
- 旧版本 wandb 只接受 **40 位 API Key**，会导致新 Key 登录失败。

因此，在当前集群环境中，即使安装过程有阻力，也必须采用上述方法将 wandb 升级到可支持新版 Key 的版本。

---

## 登录建议

```bash
wandb login
```

如需在非交互任务（如 `sbatch`）中使用，可在作业脚本中设置：

```bash
export WANDB_API_KEY="你的_api_key"
```

---

## 结论

在受限集群环境里，安装最新版 wandb 的重点不在“单条命令升级”，而在于：

1. 规避本地构建的易失败环节（如 `gpu_stats`）；
2. 使用官方源与重试参数提升成功率；
3. 保证 wandb 版本足够新，以支持 **86 位 API Key** 登录。
