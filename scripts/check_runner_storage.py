#!/usr/bin/env python3
"""Reject native validation without usable disk headroom; never delete files."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import uuid


GIB = 1024 ** 3
MINIMUM_FREE_BYTES = 20 * GIB


def assess_capacity(label, total, free):
    result = {"volume": label, "status": "unavailable"}
    if (type(total) is not int or type(free) is not int
            or total <= 0 or free < 0 or free > total):
        return result
    # Engineering headroom policy, not a claim about macOS's purge threshold.
    required = max(MINIMUM_FREE_BYTES, (total + 9) // 10)
    result.update(totalBytes=total, availableBytes=free, requiredBytes=required,
                  status="pass" if free >= required else "insufficient")
    return result


def inspect_capacity(label, path):
    try:
        usage = shutil.disk_usage(path)
    except OSError:
        # Exceptions can contain paths; retain only the failure category.
        return {"volume": label, "status": "unavailable"}
    return assess_capacity(label, usage.total, usage.free)


def run_preflight(workspace, temporary):
    volumes = [inspect_capacity("workspace", workspace),
               inspect_capacity("temporary", temporary)]
    passed = all(volume["status"] == "pass" for volume in volumes)
    report = {
        "schema": 1,
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "policy": {"minimumFreeBytes": MINIMUM_FREE_BYTES, "minimumFreePercent": 10},
        "status": "pass" if passed else "fail",
        "volumes": volumes,
    }
    encoded = json.dumps(report, indent=2) + "\n"
    print(encoded, end="")
    try:
        directory = workspace / "build/logs"
        directory.mkdir(parents=True, exist_ok=True)
        # A fresh report preserves earlier invocations and changed conditions.
        with (directory / f"runner-storage-{uuid.uuid4()}.json").open("x") as output:
            output.write(encoded)
    except OSError:
        print("Storage preflight failed: could not retain its capacity report.")
        return 1
    if not passed:
        print("Storage preflight failed. Restore disk headroom before native validation; "
              "retain test evidence and do not delete user files or unrelated project caches.")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(run_preflight(Path(__file__).resolve().parents[1],
                                  Path(os.environ.get("TMPDIR") or "/tmp")))
