#!/usr/bin/env python3
"""Compare complete TextKit 2 layout with wrapping enabled and disabled."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

REPO = Path(subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True,
).stdout.strip())
SOURCE = REPO / "docs/validation/reproducers/TextKit2WrapControlProbe.swift"
os.umask(0o077)
RUN = REPO / "build/logs" / f"TextKit2WrapControl-{uuid.uuid4().upper()}"
RUN.mkdir(mode=0o700, parents=True)
(RUN / "tmp").mkdir(mode=0o700)
(RUN / "module-cache").mkdir(mode=0o700)
BINARY = RUN / "TextKit2WrapControlProbe"
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
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-O", "-module-cache-path",
        str(RUN / "module-cache"), str(SOURCE), "-framework", "AppKit", "-o", str(BINARY),
    ], cwd=REPO, env=ENV, capture_output=True, check=False, timeout=90,
)
(RUN / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
result = {
    "kind": "generated TextKit 2 long-paragraph wrap control",
    "sourceSHA256": sha(SOURCE),
    "binarySHA256": sha(BINARY) if BINARY.exists() else None,
    "sizesBytes": [16_384, 1_048_576, 10_485_760],
    "modes": ["wrap", "no-wrap"],
    "timeoutSecondsPerCell": 12,
    "compileExitCode": compiled.returncode,
    "applicationAcceptance": False,
    "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "cases": [],
}
if compiled.returncode == 0:
    for size in result["sizesBytes"]:
        for mode in result["modes"]:
            name = f"{size}-{mode}"
            case = {"requestedUTF8Bytes": size, "wrapMode": mode}
            started = time.monotonic()
            try:
                process = subprocess.run(
                    [str(BINARY), str(size), mode], cwd=REPO, env=ENV,
                    capture_output=True, timeout=result["timeoutSecondsPerCell"], check=False,
                )
                (RUN / f"{name}.stdout").write_bytes(process.stdout)
                (RUN / f"{name}.stderr").write_bytes(process.stderr)
                case.update(
                    status="exited", exitCode=process.returncode,
                    elapsedSeconds=round(time.monotonic() - started, 6),
                )
                try:
                    case["observations"] = json.loads(process.stdout)
                except json.JSONDecodeError:
                    case["observations"] = None
            except subprocess.TimeoutExpired as error:
                (RUN / f"{name}.stdout").write_bytes(error.stdout or b"")
                (RUN / f"{name}.stderr").write_bytes(error.stderr or b"")
                case.update(status="timedOut", elapsedSeconds=round(time.monotonic() - started, 6))
            result["cases"].append(case)

result["finishedAt"] = dt.datetime.now(dt.timezone.utc).isoformat()
(RUN / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(json.dumps({
    "artifactDirectory": str(RUN),
    "compileExitCode": result["compileExitCode"],
    "cases": len(result["cases"]),
    "statuses": [case["status"] for case in result["cases"]],
}))
raise SystemExit(0 if compiled.returncode == 0 else 1)
