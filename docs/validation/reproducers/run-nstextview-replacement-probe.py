#!/usr/bin/env python3
"""Probe replacing TextKit 2 content storage after NSTextView initialization."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

REPO = Path(subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True,
).stdout.strip())
SOURCE = REPO / "docs/validation/reproducers/NSTextViewReplaceManagerProbe.swift"
os.umask(0o077)
RUN = REPO / "build/logs" / f"NSTextViewReplaceManager-{str(uuid.uuid4()).upper()}"
RUN.mkdir(mode=0o700, parents=True)
(RUN / "tmp").mkdir(mode=0o700)
(RUN / "module-cache").mkdir(mode=0o700)
shutil.copy2(SOURCE, RUN / SOURCE.name)
BINARY = RUN / "NSTextViewReplaceManagerProbe"
ENV = {
    "DEVELOPER_DIR": "/Applications/Xcode_26.6.app/Contents/Developer",
    "HOME": str(RUN),
    "TMPDIR": str(RUN / "tmp"),
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "LANG": "en_US.UTF-8",
    "LC_ALL": "en_US.UTF-8",
}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


compiled = subprocess.run(
    [
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-O",
        "-module-cache-path", str(RUN / "module-cache"), str(SOURCE), "-framework", "AppKit",
        "-o", str(BINARY),
    ], cwd=REPO, env=ENV, capture_output=True, check=False, timeout=90,
)
(RUN / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
if compiled.returncode == 0:
    shutil.rmtree(RUN / "module-cache")
result = {
    "kind": "generated NSTextView TextKit 2 replacement-manager control",
    "sourceSHA256": sha(SOURCE),
    "binarySHA256": sha(BINARY) if BINARY.exists() else None,
    "cells": [
        {"requestedUTF8Bytes": 16_384, "targetMode": "full"},
        {"requestedUTF8Bytes": 10_485_760, "targetMode": "viewport"},
    ],
    "timeoutSecondsPerCell": 12,
    "compileExitCode": compiled.returncode,
    "applicationAcceptance": False,
    "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "outcomes": [],
}
if compiled.returncode == 0:
    for cell in result["cells"]:
        name = f"{cell['requestedUTF8Bytes']}-{cell['targetMode']}"
        started = time.monotonic()
        outcome = dict(cell)
        try:
            process = subprocess.run(
                [str(BINARY), str(cell["requestedUTF8Bytes"]), cell["targetMode"]],
                cwd=REPO, env=ENV, capture_output=True,
                timeout=result["timeoutSecondsPerCell"], check=False,
            )
            (RUN / f"{name}.stdout").write_bytes(process.stdout)
            (RUN / f"{name}.stderr").write_bytes(process.stderr)
            outcome.update(
                status="exited", exitCode=process.returncode,
                elapsedSeconds=round(time.monotonic() - started, 6),
            )
            try:
                outcome["observations"] = json.loads(process.stdout)
            except json.JSONDecodeError:
                outcome["observations"] = None
        except subprocess.TimeoutExpired as error:
            (RUN / f"{name}.stdout").write_bytes(error.stdout or b"")
            (RUN / f"{name}.stderr").write_bytes(error.stderr or b"")
            outcome.update(
                status="timedOut", elapsedSeconds=round(time.monotonic() - started, 6),
            )
        result["outcomes"].append(outcome)
        print(json.dumps(outcome, sort_keys=True), flush=True)

result["finishedAt"] = dt.datetime.now(dt.timezone.utc).isoformat()
(RUN / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(json.dumps({
    "artifactDirectory": str(RUN),
    "compileExitCode": result["compileExitCode"],
    "statuses": [outcome.get("status") for outcome in result["outcomes"]],
}))
raise SystemExit(0 if compiled.returncode == 0 else 1)
