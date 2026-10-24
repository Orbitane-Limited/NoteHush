#!/usr/bin/env python3
"""Privately retain generated, headless TextKit 2 virtual-element observations."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "VirtualParagraphProbe.swift"
BINARY = ROOT / "VirtualParagraphProbe"
RUN = ROOT / f"VirtualParagraphProbe-{uuid.uuid4()}"
RUN.mkdir(mode=0o700)
PRIVATE_TMP = RUN / "tmp"
PRIVATE_TMP.mkdir(mode=0o700)
shutil.copy2(SOURCE, RUN / SOURCE.name)
shutil.copy2(BINARY, RUN / BINARY.name)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


plan = {
    "kind": "Generated AppKit TextKit 2 custom-content-manager experiment",
    "fixture": "16-byte header followed by repeated generated Arabic/emoji units",
    "sourceSHA256": sha(SOURCE),
    "binarySHA256": sha(BINARY),
    "cases": [
        {"bytes": 16_384, "chunkUTF16": 0, "timeoutSeconds": 10},
        {"bytes": 16_384, "chunkUTF16": 4_032, "timeoutSeconds": 10},
        {"bytes": 16_384, "chunkUTF16": 96, "timeoutSeconds": 10},
        {"bytes": 262_144, "chunkUTF16": 4_032, "timeoutSeconds": 10},
        {"bytes": 1_048_576, "chunkUTF16": 4_032, "timeoutSeconds": 10},
        {"bytes": 10_485_760, "chunkUTF16": 4_032, "timeoutSeconds": 10},
        {"bytes": 10_485_760, "chunkUTF16": 1_536, "timeoutSeconds": 10},
        {"bytes": 10_485_760, "chunkUTF16": 768, "timeoutSeconds": 10},
        {"bytes": 10_485_760, "chunkUTF16": 384, "timeoutSeconds": 10},
    ],
    "oneFreshProcessPerCell": True,
    "generatedTextOnly": True,
    "noWindowsOrInput": True,
    "productCodeChanged": False,
    "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
}
(RUN / "plan.json").write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
records = []
with (RUN / "observations.jsonl").open("w") as journal:
    for case in plan["cases"]:
        command = [str(BINARY), str(case["bytes"]), str(case["chunkUTF16"])]
        start = time.monotonic()
        try:
            proc = subprocess.run(
                command,
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
            elapsed = time.monotonic() - start
            record = {
                **case,
                "status": "exited",
                "exitCode": proc.returncode,
                "elapsedSeconds": round(elapsed, 6),
                "stdout": proc.stdout.decode("utf-8", "replace"),
                "stderr": proc.stderr.decode("utf-8", "replace"),
            }
        except subprocess.TimeoutExpired as error:
            elapsed = time.monotonic() - start
            record = {
                **case,
                "status": "timedOut",
                "elapsedSeconds": round(elapsed, 6),
                "timeoutSeconds": case["timeoutSeconds"],
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
    "allProductAcceptance": False,
}
(RUN / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
(ROOT / "latest-virtual-paragraph-probe.json").write_text(
    json.dumps({"root": str(RUN)}, indent=2) + "\n"
)
print(json.dumps({"root": str(RUN), "records": len(records), "statuses": [r["status"] for r in records]}))
