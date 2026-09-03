#!/wangxuanxu/miniconda3/envs/clusterx-cli/bin/python
"""Single-screen ClusterX team GPU dashboard."""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from rich import box
from rich.columns import Columns
from rich.console import Console, Group
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from clusterx.launcher.ssp.ssp import SSPCluster


DEFAULT_QUEUE = "queue-t-reserved-wammodel"
# Transitional jobs may still own devices until the scheduler releases their pods.
ACTIVE_STATES = ("RUNNING", "RESTARTING", "COMPLETING", "TERMINATING")
QUEUED_STATES = ("PENDING",)


@dataclass(frozen=True)
class Job:
    name: str
    user: str
    state: str
    queue: str
    nodes: int
    gpus: int
    shape: str


@dataclass(frozen=True)
class NodeTotals:
    nodes: int
    total_gpu: int
    allocated_gpu: int
    unhealthy_nodes: int
    reported_total_nodes: int


def _as_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _fetch_jobs_for_state(cluster: SSPCluster, state: str) -> list[dict[str, Any]]:
    """Fetch every job page; ClusterX 2026.7.28 otherwise keeps only page one."""
    path = f"{cluster.client._get_base_path()}trainingJobs"
    token: str | None = None
    seen_tokens: set[str] = set()
    jobs: list[dict[str, Any]] = []

    while True:
        params: dict[str, Any] = {"filter": f'state="{state}"', "pageSize": 100}
        if token:
            params["pageToken"] = token
        response = cluster.client._make_request("GET", path, params=params)
        page = response.get("training_jobs") or response.get("trainingJobs") or []
        jobs.extend(page)
        token = response.get("next_page_token") or response.get("nextPageToken")
        if not token:
            return jobs
        if token in seen_tokens:
            raise RuntimeError(f"Job API returned a repeated page token for {state}")
        seen_tokens.add(token)


def _parse_jobs(raw_jobs: list[dict[str, Any]], queue: str) -> list[Job]:
    parsed: list[Job] = []
    for raw in raw_jobs:
        spec = raw.get("spec") or {}
        queue_id = ((spec.get("queue") or {}).get("id") or "")
        partition = str(queue_id).split("/")[-1] if queue_id else "unknown"
        if partition != queue:
            continue
        tasks = ((spec.get("vc_job") or {}).get("tasks") or [])
        nodes = 0
        gpus = 0
        shapes: list[str] = []
        for task in tasks:
            replicas = _as_int(task.get("replicas"))
            per_node = _as_int((task.get("resource_spec") or {}).get("accelerate_device_count"))
            nodes += replicas
            gpus += replicas * per_node
            if replicas:
                shapes.append(f"{replicas}×{per_node}")
        state = str((raw.get("status") or {}).get("state") or "UNKNOWN").upper()
        parsed.append(
            Job(
                name=str(raw.get("display_name") or raw.get("name") or "<unnamed>"),
                user=str((raw.get("ownership") or {}).get("creator_name") or "<unknown>"),
                state=state,
                queue=partition,
                nodes=nodes,
                gpus=gpus,
                shape="+".join(shapes) or "0×0",
            )
        )
    return parsed


def fetch_jobs(cluster: SSPCluster, queue: str) -> tuple[list[Job], list[Job]]:
    active_raw: list[dict[str, Any]] = []
    queued_raw: list[dict[str, Any]] = []
    for state in ACTIVE_STATES:
        active_raw.extend(_fetch_jobs_for_state(cluster, state))
    for state in QUEUED_STATES:
        queued_raw.extend(_fetch_jobs_for_state(cluster, state))
    return _parse_jobs(active_raw, queue), _parse_jobs(queued_raw, queue)


def fetch_node_totals(cluster: SSPCluster, queue: str) -> NodeTotals:
    """Fetch up to 100 bound nodes, avoiding the server's default page size of 10."""
    response = cluster.client.list_queue_nodes(
        cluster=cluster.cfg["cluster"], queue=queue, page_size=100, is_bound=True
    )
    nodes = response.get("nodes") or []
    reported = _as_int(response.get("total_size") or response.get("totalSize") or len(nodes))
    total_gpu = 0
    allocated_gpu = 0
    unhealthy = 0
    for node in nodes:
        if str(node.get("state") or "") in {"NotReady", "SchedulingDisabled"}:
            unhealthy += 1
        for resource in node.get("summary_data") or []:
            if str(resource.get("resource_type") or "").upper() == "DEVICE":
                total_gpu += _as_int(resource.get("total"))
                allocated_gpu += _as_int(resource.get("allocated"))
    return NodeTotals(len(nodes), total_gpu, allocated_gpu, unhealthy, reported)


def _metric(label: str, value: str, color: str = "cyan") -> Text:
    text = Text()
    text.append(f"{label} ", style="dim")
    text.append(value, style=f"bold {color}")
    return text


def _summary_panel(nodes: NodeTotals, active: list[Job], queued: list[Job], elapsed: float) -> Panel:
    running_request = sum(job.gpus for job in active)
    queued_request = sum(job.gpus for job in queued)
    free = max(nodes.total_gpu - nodes.allocated_gpu, 0)
    grid = Table.grid(expand=True)
    for _ in range(6):
        grid.add_column(justify="center")
    grid.add_row(
        _metric("总 GPU", str(nodes.total_gpu), "white"),
        _metric("已分配", str(nodes.allocated_gpu), "red"),
        _metric("剩余", str(free), "green"),
        _metric("运行申请", str(running_request), "magenta"),
        _metric("排队计划", str(queued_request), "yellow"),
        _metric("节点", f"{nodes.nodes}/{nodes.reported_total_nodes}", "blue"),
    )
    subtitle = f"抓取 {elapsed:.1f}s"
    delta = nodes.allocated_gpu - running_request
    if delta:
        subtitle += f" · 节点/Job 差额 {delta:+d} GPU"
    if nodes.unhealthy_nodes:
        subtitle += f" · 异常节点 {nodes.unhealthy_nodes}"
    return Panel(grid, title="团队 GPU 总览", subtitle=subtitle, border_style="blue", padding=(0, 1))


def _user_rows(active: list[Job], queued: list[Job]) -> list[tuple[str, int, int, int, int]]:
    usage: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for job in active:
        if job.gpus == 0:
            continue
        usage[job.user]["active_gpu"] += job.gpus
        usage[job.user]["active_jobs"] += 1
    for job in queued:
        if job.gpus == 0:
            continue
        usage[job.user]["queued_gpu"] += job.gpus
        usage[job.user]["queued_jobs"] += 1
    rows = [
        (
            user,
            values["active_gpu"],
            values["queued_gpu"],
            values["active_jobs"],
            values["queued_jobs"],
        )
        for user, values in usage.items()
    ]
    return sorted(rows, key=lambda row: (-row[1], -row[2], row[0]))


def _user_table(
    rows: list[tuple[str, int, int, int, int]],
    title: str | None = None,
    compact: bool = False,
) -> Table:
    table = Table(
        title=title,
        box=None if compact else box.SIMPLE_HEAVY,
        show_edge=False,
        pad_edge=False,
        collapse_padding=compact,
    )
    table.add_column("用户", style="bold", no_wrap=True)
    table.add_column("占用", justify="right", style="magenta")
    table.add_column("排队", justify="right", style="yellow")
    table.add_column("任务(运/排)", justify="right", style="dim")
    for user, active_gpu, queued_gpu, active_jobs, queued_jobs in rows:
        table.add_row(user, str(active_gpu), str(queued_gpu), f"{active_jobs}/{queued_jobs}")
    if not rows:
        table.add_row("无活动用户", "0", "0", "0/0")
    return table


def _users_panel(rows: list[tuple[str, int, int, int, int]], terminal_height: int) -> Panel:
    # Split into side-by-side tables before vertical overflow. This keeps all users visible.
    rows_per_table = max(6, terminal_height - 17)
    chunks = [rows[i : i + rows_per_table] for i in range(0, len(rows), rows_per_table)] or [[]]
    tables = [_user_table(chunk) for chunk in chunks]
    return Panel(
        Columns(tables, equal=True, expand=True, padding=(0, 2)),
        title=f"按用户汇总（{len(rows)} 人）",
        border_style="magenta",
        padding=(0, 1),
    )


def _queued_table(queued: list[Job], compact: bool = False) -> Table:
    table = Table(
        box=None if compact else box.SIMPLE,
        show_edge=False,
        pad_edge=False,
        expand=True,
        collapse_padding=compact,
    )
    table.add_column("用户", no_wrap=True)
    table.add_column("排队任务", overflow="ellipsis", no_wrap=True, ratio=1)
    table.add_column("GPU", justify="right", style="yellow")
    table.add_column("节点×卡", justify="right", style="dim")
    for job in sorted(queued, key=lambda item: (-item.gpus, item.user, item.name)):
        table.add_row(job.user, job.name, str(job.gpus), job.shape)
    if not queued:
        table.add_row("—", "当前没有排队任务", "0", "—")
    return table


def _compact_dashboard(
    heading: Text,
    nodes: NodeTotals,
    active: list[Job],
    queued: list[Job],
    cpu_only_queued: int,
) -> Group:
    user_rows = _user_rows(active, queued)
    midpoint = (len(user_rows) + 1) // 2
    user_tables = [
        _user_table(user_rows[:midpoint], compact=True),
        _user_table(user_rows[midpoint:], compact=True),
    ]
    running_request = sum(job.gpus for job in active)
    queued_request = sum(job.gpus for job in queued)
    free = max(nodes.total_gpu - nodes.allocated_gpu, 0)
    delta = nodes.allocated_gpu - running_request
    summary = Text.assemble(
        ("GPU 总/占/余 ", "dim"),
        (f"{nodes.total_gpu}/{nodes.allocated_gpu}/{free}", "bold cyan"),
        ("  Job 运/排 ", "dim"),
        (f"{running_request}/{queued_request}", "bold magenta"),
        ("  节点 ", "dim"),
        (f"{nodes.nodes}/{nodes.reported_total_nodes}", "bold blue"),
        ("  差额 ", "dim"),
        (f"{delta:+d}", "yellow" if delta else "green"),
    )
    user_title = Text(f"用户占用/排队 GPU（{len(user_rows)} 人）", style="bold magenta")
    queue_title = Text(
        f"GPU 排队任务（{len(queued)} 个，计划 {queued_request} GPU）", style="bold yellow"
    )
    note = Text(f"另有 {cpu_only_queued} 个排队 CPU-only Job 未展开。", style="dim")
    return Group(
        heading,
        summary,
        user_title,
        Columns(user_tables, equal=True, expand=True, padding=(0, 1)),
        queue_title,
        _queued_table(queued, compact=True),
        note,
    )


def render_dashboard(cluster: SSPCluster, queue: str) -> Group:
    started = time.monotonic()
    active, queued = fetch_jobs(cluster, queue)
    nodes = fetch_node_totals(cluster, queue)
    gpu_queued = [job for job in queued if job.gpus > 0]
    cpu_only_queued = len(queued) - len(gpu_queued)
    elapsed = time.monotonic() - started
    terminal = shutil.get_terminal_size((160, 45))
    now = datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y-%m-%d %H:%M:%S")
    heading = Text.assemble(
        ("ClusterX 团队资源看板", "bold white"),
        (f"  {queue}", "cyan"),
        (f"  北京时间 {now}", "dim"),
    )
    if terminal.lines < 35:
        return _compact_dashboard(heading, nodes, active, gpu_queued, cpu_only_queued)
    users = _users_panel(_user_rows(active, gpu_queued), terminal.lines)
    queued_panel = Panel(
        _queued_table(gpu_queued),
        title=f"GPU 排队任务（{len(gpu_queued)} 个，计划 {sum(j.gpus for j in gpu_queued)} GPU）",
        border_style="yellow",
        padding=(0, 1),
    )
    note = Text(
        (
            "占用=尚未释放资源的 Job 申请量；已分配/剩余=节点调度数据；"
            f"排队=PENDING 计划量；另有 {cpu_only_queued} 个排队 CPU-only Job 未展开；"
            "节点/Job 差额可能来自接口时序或当前 workspace 不可见的占用。"
        ),
        style="dim",
    )
    return Group(heading, _summary_panel(nodes, active, queued, elapsed), users, queued_panel, note)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ClusterX 团队 GPU 单屏资源看板")
    parser.add_argument("-q", "--queue", default=DEFAULT_QUEUE, help="ClusterX 队列名")
    parser.add_argument(
        "-w",
        "--watch",
        nargs="?",
        const=10.0,
        type=float,
        metavar="SECONDS",
        help="持续刷新；默认间隔 10 秒",
    )
    parser.add_argument("--no-color", action="store_true", help="禁用 ANSI 颜色")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.watch is not None and args.watch < 2:
        print("刷新间隔不得小于 2 秒，以免压垮管理接口。", file=sys.stderr)
        return 2
    console = Console(no_color=args.no_color)
    cluster = SSPCluster()

    if args.watch is None:
        console.print(render_dashboard(cluster, args.queue))
        return 0

    try:
        while True:
            try:
                dashboard = render_dashboard(cluster, args.queue)
                console.clear()
                console.print(dashboard)
            except Exception as exc:  # keep the monitor alive through transient API errors
                console.clear()
                console.print(Panel(str(exc), title="刷新失败，将自动重试", border_style="red"))
            time.sleep(args.watch)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
