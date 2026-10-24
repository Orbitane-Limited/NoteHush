#!/usr/bin/env python3
"""Capture bounded full malloc histories for live app-owned allocations."""

from __future__ import annotations

import argparse
from collections.abc import Callable
import re
import subprocess
from pathlib import Path
from xml.etree import ElementTree


ADDRESS = re.compile(r"0[xX][0-9a-fA-F]+\Z")


def app_allocations(xml_path: Path, image_name: str, limit: int) -> list[dict[str, str]]:
    """Return the largest live, uniquely attributed app allocations."""
    if limit < 1:
        raise ValueError("allocation sample limit must be positive")
    largest_by_caller: dict[str, dict[str, str]] = {}
    for row in ElementTree.parse(xml_path).iter("row"):
        values = row.attrib
        address = values.get("address", "")
        caller = values.get("responsible-caller", "")
        if (
            values.get("live") != "true"
            or values.get("responsible-library") != image_name
            or not ADDRESS.fullmatch(address)
            or not caller
        ):
            continue
        try:
            size = int(values["size"])
        except (KeyError, ValueError):
            continue
        if size <= 0:
            continue
        prior = largest_by_caller.get(caller)
        if prior is None or size > int(prior["size"]):
            largest_by_caller[caller] = {
                "address": address,
                "caller": caller,
                "size": str(size),
            }
    return sorted(
        largest_by_caller.values(), key=lambda item: int(item["size"]), reverse=True
    )[:limit]


def collect(
    pid: int,
    xml_path: Path,
    output_path: Path,
    *,
    image_name: str = "NoteHushPerformance",
    limit: int = 8,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> int:
    """Write malloc_history output while the exact profiled process is alive."""
    if pid < 1:
        raise ValueError("process ID must be positive")
    candidates = app_allocations(xml_path, image_name, limit)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    failures = 0
    with output_path.open("w", encoding="utf-8") as output:
        output.write(
            f"schema=1\npid={pid}\nimage={image_name}\n"
            f"source_allocations={len(candidates)}\n"
        )
        if not candidates:
            output.write("status=noLiveAppAllocations\n")
            return 1
        for candidate in candidates:
            output.write(
                "\n"
                f"=== address={candidate['address']} size={candidate['size']} "
                f"responsible-caller={candidate['caller']} ===\n"
            )
            command = [
                "/usr/bin/sudo",
                "-n",
                "/usr/bin/malloc_history",
                str(pid),
                "-fullStacks",
                candidate["address"],
            ]
            try:
                result = runner(
                    command, capture_output=True, text=True, check=False, timeout=10
                )
            except (OSError, subprocess.TimeoutExpired) as error:
                failures += 1
                output.write(f"status=failed reason={type(error).__name__}\n")
                for stream_name in ("stdout", "stderr"):
                    partial = getattr(error, stream_name, None)
                    if partial:
                        if isinstance(partial, bytes):
                            partial = partial.decode("utf-8", errors="replace")
                        output.write(f"--- partial {stream_name} ---\n{partial}\n")
                output.flush()
                break
            output.write(f"exit_status={result.returncode}\n")
            output.write(result.stdout)
            if result.stderr:
                output.write("\n--- stderr ---\n")
                output.write(result.stderr)
            if result.returncode != 0 or not result.stdout.strip():
                failures += 1
                output.flush()
                break
            output.flush()
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pid", type=int)
    parser.add_argument("allocations_xml", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--image-name", default="NoteHushPerformance")
    parser.add_argument("--limit", type=int, default=8)
    args = parser.parse_args()
    try:
        status = collect(
            args.pid,
            args.allocations_xml,
            args.output,
            image_name=args.image_name,
            limit=args.limit,
        )
    except (OSError, ElementTree.ParseError, ValueError) as error:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            f"schema=1\npid={args.pid}\nstatus=failed reason={type(error).__name__}\n",
            encoding="utf-8",
        )
        return 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
