#!/usr/bin/env python3
"""Retain generated, headless TextKit 2 viewport-only layout observations."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "VirtualParagraphViewportProbe.swift"
REPO = Path(subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], cwd=ROOT,
    check=True, capture_output=True, text=True,
).stdout.strip())
ARTIFACT_ROOT = REPO / "build"
RUN = ARTIFACT_ROOT / f"VirtualParagraphViewportProbe-{uuid.uuid4()}"
RUN.mkdir(mode=0o700)
PRIVATE_TMP = RUN / "tmp"
PRIVATE_TMP.mkdir(mode=0o700)
BINARY = RUN / "VirtualParagraphViewportProbe"
shutil.copy2(SOURCE, RUN / SOURCE.name)

compile_process = subprocess.run(
    [
        "xcrun", "swiftc", "-O", "-module-cache-path", str(RUN / "module-cache"),
        str(SOURCE), "-framework", "AppKit", "-o", str(BINARY),
    ],
    cwd=REPO,
    env={
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(RUN),
        "TMPDIR": str(PRIVATE_TMP),
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8",
        "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
    },
    capture_output=True,
    check=False,
)
(RUN / "compile.log").write_bytes(compile_process.stdout + compile_process.stderr)
if compile_process.returncode != 0:
    print(json.dumps({"root": str(RUN), "compileExitCode": compile_process.returncode}))
    raise SystemExit(compile_process.returncode)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


cases = [
    {"bytes": 10_485_760, "chunkUTF16": chunk, "mode": mode, "timeoutSeconds": 10}
    for chunk in (384, 768, 1_536, 4_032)
    for mode in ("viewport-header", "viewport-start", "viewport-middle", "viewport-end")
]
plan = {
    "kind": "Generated AppKit TextKit 2 custom-content-manager viewport experiment",
    "fixture": "16-byte header followed by exact repeated generated Arabic/emoji units",
    "sourceSHA256": sha(SOURCE),
    "binarySHA256": sha(BINARY),
    "cases": cases,
    "oneFreshProcessPerCell": True,
    "exactSourceBytesAndTargetLineCoverageRequired": True,
    "generatedTextOnly": True,
    "noWindowsOrInput": True,
    "productCodeChanged": False,
    "compileExitCode": compile_process.returncode,
    "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
}
(RUN / "plan.json").write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
records = []
with (RUN / "observations.jsonl").open("w") as journal:
    for case in cases:
        started = time.monotonic()
        try:
            proc = subprocess.run(
                [str(BINARY), str(case["bytes"]), str(case["chunkUTF16"]), case["mode"]],
                cwd=ROOT,
                env={
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME": str(RUN),
                    "TMPDIR": str(PRIVATE_TMP),
                    "LANG": "en_US.UTF-8",
                    "LC_ALL": "en_US.UTF-8",
                },
                capture_output=True,
                timeout=case["timeoutSeconds"],
                check=False,
            )
            record = {
                **case,
                "status": "exited",
                "exitCode": proc.returncode,
                "elapsedSeconds": round(time.monotonic() - started, 6),
                "stdout": proc.stdout.decode("utf-8", "replace"),
                "stderr": proc.stderr.decode("utf-8", "replace"),
            }
        except subprocess.TimeoutExpired as error:
            record = {
                **case,
                "status": "timedOut",
                "elapsedSeconds": round(time.monotonic() - started, 6),
                "stdout": (error.stdout or b"").decode("utf-8", "replace"),
                "stderr": (error.stderr or b"").decode("utf-8", "replace"),
            }
        records.append(record)
        journal.write(json.dumps(record, sort_keys=True) + "\n")
        journal.flush()

result = {
    "sourceSHA256": sha(SOURCE),
    "binarySHA256": sha(BINARY),
    "records": records,
    "finishedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "applicationAcceptance": False,
}
(RUN / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
(ARTIFACT_ROOT / "latest-virtual-paragraph-viewport-probe.json").write_text(
    json.dumps({"root": str(RUN)}, indent=2) + "\n"
)
print(json.dumps({"root": str(RUN), "cases": len(records), "statusCounts": {
    status: sum(record["status"] == status for record in records)
    for status in sorted({record["status"] for record in records})
}}))
