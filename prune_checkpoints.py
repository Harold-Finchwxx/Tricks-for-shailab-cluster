#!/usr/bin/env python3
"""
当指定目录下 .pt / .ckpt 等检查点文件数量超过上限时，按修改时间删除最旧的文件。
可同时指定多个目录；--max 对每个目录分别生效。

默认只扫描各 DIR 的「直接子文件」；要包含子目录请加 -r / --recursive。

用法示例:
  python prune_checkpoints.py /path/a /path/b --max 5
  python prune_checkpoints.py /path/to/ckpts --max 5 --once
  python prune_checkpoints.py /path/to/ckpts --max 5 --dry-run
  python prune_checkpoints.py /path/to/ckpts --max 5 -r
  python prune_checkpoints.py /path/a --max 5 --interval 300   # 每 300 秒扫一次（Ctrl+C 结束）
  # 也可用系统定时任务单次调用本脚本，见 --help 说明
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


def collect_checkpoint_files(
    root: Path,
    extensions: frozenset[str],
    recursive: bool,
) -> list[Path]:
    if recursive:
        paths: list[Path] = []
        for ext in extensions:
            paths.extend(root.rglob(f"*{ext}"))
        return list({p.resolve() for p in paths if p.is_file()})
    return [
        p
        for p in root.iterdir()
        if p.is_file() and p.suffix.lower() in extensions
    ]


def prune_one_directory(
    root: Path,
    extensions: frozenset[str],
    recursive: bool,
    max_keep: int,
    once: bool,
    dry_run: bool,
) -> int:
    """处理单个目录，返回 0 成功，1 删除失败。"""

    files = collect_checkpoint_files(root, extensions, recursive)
    files.sort(key=lambda p: p.stat().st_mtime)

    over = len(files) - max_keep
    if over <= 0:
        print(f"当前 {len(files)} 个文件，未超过上限 {max_keep}，无需删除。")
        return 0

    if once:
        to_remove = [files[0]]
    else:
        to_remove = files[:over]

    def display_path(path: Path) -> Path:
        try:
            return path.relative_to(root)
        except ValueError:
            return path

    for path in to_remove:
        rel = display_path(path)
        if dry_run:
            print(f"[dry-run] 将删除: {rel}")
        else:
            try:
                path.unlink()
                print(f"已删除: {rel}")
            except OSError as e:
                print(f"删除失败 {rel}: {e}", file=sys.stderr)
                return 1

    if dry_run:
        print(f"[dry-run] 共 {len(to_remove)} 个文件（当前多 {over} 个）。")
    return 0


def run_one_pass(
    roots: list[Path],
    extensions: frozenset[str],
    recursive: bool,
    max_keep: int,
    once: bool,
    dry_run: bool,
) -> int:
    exit_code = 0
    for i, root in enumerate(roots):
        if len(roots) > 1:
            print(f"--- 目录 {i + 1}/{len(roots)}: {root} ---")
        rc = prune_one_directory(
            root,
            extensions,
            recursive,
            max_keep,
            once,
            dry_run,
        )
        if rc != 0:
            exit_code = 1
    return exit_code


def main() -> int:
    parser = argparse.ArgumentParser(
        description="检查点文件数量超过上限时，按 mtime 删除最旧的文件（可多目录，各自独立计数）。",
    )
    parser.add_argument(
        "directories",
        type=Path,
        nargs="+",
        metavar="DIR",
        help="要扫描的一个或多个目录",
    )
    parser.add_argument(
        "--max",
        type=int,
        required=True,
        metavar="N",
        help="每个目录允许保留的最多文件数（超过则删除最旧的）",
    )
    parser.add_argument(
        "--ext",
        default=".pt,.ckpt",
        help="逗号分隔的后缀列表，默认: .pt,.ckpt",
    )
    parser.add_argument(
        "-r",
        "--recursive",
        action="store_true",
        help="递归扫描子目录",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="仅当超限时删除 1 个最旧文件（默认会删到数量不超过上限）",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只打印将要删除的文件，不真正删除",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=None,
        metavar="SEC",
        help="每隔 SEC 秒重复扫描并执行（前台常驻进程，Ctrl+C 停止）。不设则只运行一次。",
    )
    args = parser.parse_args()

    if args.max < 0:
        print("错误: --max 不能为负数", file=sys.stderr)
        return 1

    raw_exts = [e.strip().lower() for e in args.ext.split(",") if e.strip()]
    extensions = frozenset(e if e.startswith(".") else f".{e}" for e in raw_exts)
    if not extensions:
        print("错误: 至少指定一个后缀（--ext）", file=sys.stderr)
        return 1

    roots: list[Path] = []
    for d in args.directories:
        root = d.expanduser().resolve()
        if not root.is_dir():
            print(f"错误: 不是有效目录: {root}", file=sys.stderr)
            return 1
        roots.append(root)

    if args.interval is not None:
        if args.interval <= 0:
            print("错误: --interval 必须为正数（秒）", file=sys.stderr)
            return 1
        print(
            f"定时模式: 每 {args.interval} 秒扫描一次，按 Ctrl+C 停止。",
            flush=True,
        )
        try:
            while True:
                run_one_pass(
                    roots,
                    extensions,
                    args.recursive,
                    args.max,
                    args.once,
                    args.dry_run,
                )
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\n已停止定时扫描。", flush=True)
            return 0

    return run_one_pass(
        roots,
        extensions,
        args.recursive,
        args.max,
        args.once,
        args.dry_run,
    )


if __name__ == "__main__":
    raise SystemExit(main())
