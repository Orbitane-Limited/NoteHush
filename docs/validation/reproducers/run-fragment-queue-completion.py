#!/usr/bin/env python3
"""Retain a bounded 60-second completion observation for a queued native fragment."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

ROOT = Path(subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True,
).stdout.strip())
SOURCE = ROOT / "docs/validation/reproducers/TextKitFragmentQueueCompletionProbe.swift"
os.umask(0o077)
RUN = ROOT / "build/logs" / f"FragmentQueueCompletion-{str(uuid.uuid4()).upper()}"
RUN.mkdir(mode=0o700, parents=True)
(RUN / "tmp").mkdir(mode=0o700)
(RUN / "module-cache").mkdir(mode=0o700)
shutil.copy2(SOURCE, RUN / SOURCE.name)
BINARY = RUN / "TextKitFragmentQueueCompletionProbe"
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


result = {
    "kind": "generated TextKit 2 asynchronous fragment completion diagnostic",
    "sourceRevision": subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, env=ENV,
        check=True, capture_output=True, text=True,
    ).stdout.strip(),
    "sourceSHA256": sha(SOURCE),
    "fixtureBytes": 10_485_760,
    "observationSeconds": 60,
    "pollIntervalMilliseconds": 200,
    "compileTimeoutSeconds": 90,
    "processTimeoutSeconds": 75,
    "applicationAcceptance": False,
    "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
}

compile_result = subprocess.run(
    [
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-O",
        "-module-cache-path", str(RUN / "module-cache"), str(SOURCE),
        "-framework", "AppKit", "-o", str(BINARY),
    ], cwd=ROOT, env=ENV, capture_output=True, check=False, timeout=90,
)
(RUN / "compile.log").write_bytes(compile_result.stdout + compile_result.stderr)
result["compileExitCode"] = compile_result.returncode
result["binarySHA256"] = sha(BINARY) if BINARY.exists() else None
if compile_result.returncode == 0:
    shutil.rmtree(RUN / "module-cache")
    started = time.monotonic()
    try:
        process = subprocess.run(
            [str(BINARY), "10485760"], cwd=ROOT, env=ENV,
            capture_output=True, check=False, timeout=75,
        )
        (RUN / "probe.stdout").write_bytes(process.stdout)
        (RUN / "probe.stderr").write_bytes(process.stderr)
        result["processExitCode"] = process.returncode
        try:
            result["observations"] = json.loads(process.stdout)
        except json.JSONDecodeError:
            result["observations"] = None
    except subprocess.TimeoutExpired as error:
        (RUN / "probe.stdout").write_bytes(error.stdout or b"")
        (RUN / "probe.stderr").write_bytes(error.stderr or b"")
        result["processExitCode"] = 124
        result["processTimedOut"] = True
    result["processElapsedSeconds"] = round(time.monotonic() - started, 6)

result["finishedAt"] = dt.datetime.now(dt.timezone.utc).isoformat()
(RUN / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(json.dumps({
    "artifactDirectory": str(RUN),
    "compileExitCode": result["compileExitCode"],
    "processExitCode": result.get("processExitCode"),
    "processElapsedSeconds": result.get("processElapsedSeconds"),
    "observations": result.get("observations"),
}, sort_keys=True), flush=True)
observation = result.get("observations")
raise SystemExit(0 if compile_result.returncode == 0 and observation
                 and observation.get("completeCoverage") is True else 1)
