#!/usr/bin/env python3
"""Compare legacy AppKit wrapping modes on generated mixed-script paragraphs."""

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
SOURCE = ROOT / "LegacyWrapModeProbe.swift"
REPO = Path(subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], cwd=ROOT,
    check=True, capture_output=True, text=True,
).stdout.strip())
RUN = REPO / "build" / f"LegacyWrapModeProbe-{uuid.uuid4()}"
RUN.mkdir(mode=0o700, parents=True)
TMP = RUN / "tmp"
TMP.mkdir(mode=0o700)
BINARY = RUN / "LegacyWrapModeProbe"
shutil.copy2(SOURCE, RUN / SOURCE.name)
ENV = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": str(RUN),
    "TMPDIR": str(TMP),
    "LANG": "en_US.UTF-8",
    "LC_ALL": "en_US.UTF-8",
    "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


compiled = subprocess.run(
    [
        "xcrun", "swiftc", "-O", "-module-cache-path", str(RUN / "module-cache"),
        str(SOURCE), "-framework", "AppKit", "-o", str(BINARY),
    ], cwd=REPO, env=ENV, capture_output=True, check=False,
)
(RUN / "compile.log").write_bytes(compiled.stdout + compiled.stderr)
result = {
    "kind": "generated AppKit TextKit 1 paragraph wrapping mode comparison",
    "sourceSHA256": sha(SOURCE),
    "binarySHA256": sha(BINARY) if BINARY.exists() else None,
    "timeoutSecondsPerCell": 10,
    "compileExitCode": compiled.returncode,
    "applicationAcceptance": False,
    "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "cases": [],
}
if compiled.returncode == 0:
    for size in (1_048_576, 10_485_760):
        for mode in ("word", "character"):
            started = time.monotonic()
            case = {"requestedUTF8Bytes": size, "wrapMode": mode}
            try:
                process = subprocess.run(
                    [str(BINARY), str(size), mode],
                    cwd=REPO, env=ENV, capture_output=True, timeout=10, check=False,
                )
                (RUN / f"{size}-{mode}.stdout").write_bytes(process.stdout)
                (RUN / f"{size}-{mode}.stderr").write_bytes(process.stderr)
                case.update(
                    status="exited", exitCode=process.returncode,
                    elapsedSeconds=round(time.monotonic() - started, 6),
                )
                try:
                    case["observations"] = json.loads(process.stdout)
                except json.JSONDecodeError:
                    case["observations"] = None
            except subprocess.TimeoutExpired as error:
                (RUN / f"{size}-{mode}.stdout").write_bytes(error.stdout or b"")
                (RUN / f"{size}-{mode}.stderr").write_bytes(error.stderr or b"")
                case.update(
                    status="timedOut", elapsedSeconds=round(time.monotonic() - started, 6))
            result["cases"].append(case)
result["finishedAt"] = dt.datetime.now(dt.timezone.utc).isoformat()
(RUN / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(json.dumps({
    "artifactDirectory": str(RUN),
    "compileExitCode": result["compileExitCode"],
    "cases": len(result["cases"]),
    "statuses": [case["status"] for case in result["cases"]],
}))
