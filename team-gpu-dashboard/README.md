# team-gpu-dashboard

ClusterX 团队 GPU 单屏资源看板。完整遍历 Job 分页，并将节点 API 的页大小设置为 100，
规避 `clusterx==2026.7.28` 只显示第一页的问题。

本工具的维护位置（SSOT）是：

```text
/wangxuanxu/tricks-for-cluster/team-gpu-dashboard/
```

持续刷新（推荐）：

```bash
team-gpu --watch 10
```

输出一次：

```bash
team-gpu
```

也可交给外部 `watch`：

```bash
watch -c -n 10 team-gpu
```

指定队列：

```bash
team-gpu -q queue-t-reserved-wammodel --watch 10
```

口径：

- `已分配/剩余` 来自队列全部节点的调度资源数据。
- `占用` 是尚未释放资源的 `RUNNING`、`RESTARTING`、`COMPLETING`、
  `TERMINATING` Job。多 task Job 按每个 task 的
  `replicas × accelerate_device_count` 分别计算后求和。
- `排队计划` 是 `PENDING` Job 的同口径求和。
- 用户表展示当前存在 GPU 占用或 GPU 排队 Job 的用户；ClusterX API 不提供无任务成员名单。
- CPU-only 排队 Job 只显示数量，不逐项展开，以保证 GPU 看板保持单屏。
- 终端高度不足 35 行时自动切换到无边框紧凑布局，用户表分栏显示。
- 节点已分配量与当前 workspace 可见 Job 申请量不一致时，页面显式显示差额，
  不把无法归属的 GPU 强行记到某个用户。
- 这是调度占用看板，不是 `nvidia-smi` 计算利用率看板。
