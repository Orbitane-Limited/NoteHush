#!/usr/bin/env python3
"""Opt-in optimized native 10 MiB opening protocol; retains all fixtures and failures."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import uuid

import check_runner_storage

ROOT = Path(__file__).resolve().parents[1]
SAFE_ENVIRONMENT = ("HOME", "TMPDIR", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL", "DEVELOPER_DIR")


def environment():
    return {key: os.environ[key] for key in SAFE_ENVIRONMENT if key in os.environ}


def capacity(workspace, temporary, reserve):
    reports = [check_runner_storage.inspect_capacity("workspace", workspace),
               check_runner_storage.inspect_capacity("temporary", temporary)]
    passed = all(item["status"] == "pass" and
                 item["availableBytes"] - item["requiredBytes"] >= reserve for item in reports)
    return dict(passed=passed, plannedAdditionalBytes=reserve, volumes=reports)


def exclusive_json(path, value):
    with path.open("x") as output:
        json.dump(value, output, indent=2)
        output.write("\n")


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def git(*arguments):
    return subprocess.run(["git", *arguments], cwd=ROOT, env=environment(), check=True,
                          capture_output=True, text=True).stdout.strip()


def execute(arguments, output, timeout):
    # Keep all output local; do not print inherited environment or fixture contents.
    with output.open("xb") as log:
        child = subprocess.Popen(arguments, cwd=ROOT, env=environment(), stdout=log,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            return 124


def main(paragraph_bytes=None):
    os.umask(0o077)
    if paragraph_bytes is not None and (paragraph_bytes < 16 or paragraph_bytes > 10 * 1024 * 1024
                                        or paragraph_bytes % 8):
        raise SystemExit("Paragraph size must be 16 bytes–10 MiB and divisible by 8")
    if os.environ.get("NOTEHUSH_EXCLUSIVE_INPUT") != "1":
        raise SystemExit("Requires NOTEHUSH_EXCLUSIVE_INPUT=1 after arranging exclusive, awake GUI use")
    if git("status", "--porcelain"):
        raise SystemExit("Requires a clean committed worktree before building")
    output = ROOT / "build/logs" / ("LargeOpen-" + str(uuid.uuid4()).upper())
    output.mkdir(parents=True, mode=0o700)
    context = dict(schema=1, status="running", startedAt=datetime.now(timezone.utc).isoformat(),
                   exclusiveInputAttested=True, workingTreeCleanBefore=True,
                   sourceBefore=git("rev-parse", "HEAD"),
                   study="long-paragraph" if paragraph_bytes is not None else "large-open",
                   requestedBytes=paragraph_bytes)
    def step(name, arguments, timeout):
        result = execute(arguments, output / (name + ".log"), timeout)
        if result != 0:
            raise RuntimeError(name)
    try:
        for stage, reserve in (("before-build", 1024 ** 3), ("before-fixtures", 512 * 1024 ** 2)):
            report = capacity(ROOT, Path(os.environ.get("TMPDIR") or "/tmp"), reserve)
            exclusive_json(output / (stage + "-storage.json"), report)
            if not report["passed"]:
                raise RuntimeError("storage-" + stage)
            if stage == "before-build":
                step("app-build", ["bash", "scripts/build_performance.sh"], 600)
                step("host-build", ["swift", "build", "-c", "release", "--product", "LargeFileOpenHarness"], 300)
        app = ROOT / "build/PerformanceDerivedData/Build/Products/ReleasePerformance/NoteHushPerformance.app"
        executable = app / "Contents/MacOS/NoteHushPerformance"
        binary_directory = subprocess.run(["swift", "build", "-c", "release", "--show-bin-path"],
                                          cwd=ROOT, env=environment(), check=True,
                                          capture_output=True, text=True).stdout.strip()
        harness = Path(binary_directory) / "LargeFileOpenHarness"
        for label in ("before", "after"):
            if label == "after":
                if git("rev-parse", "HEAD") != context["sourceBefore"] or git("status", "--porcelain"):
                    raise RuntimeError("source-changed-before-launch")
                arguments = [str(harness), str(app), str(output)]
                if paragraph_bytes is not None:
                    arguments.extend(["--paragraph", str(paragraph_bytes)])
                context["collectorExitCode"] = execute(
                    arguments, output / "collector.log", 2250)
            step("signature-" + label, [sys.executable, "scripts/verify_test_app.py", str(app),
                                       "--configuration", "ReleasePerformance"], 30)
            context["signature" + label.title() + "Passed"] = True
            context["binary" + label.title()] = digest(executable)
            context["harness" + label.title()] = digest(harness)
        context["sourceAfter"] = git("rev-parse", "HEAD")
        context["workingTreeCleanAfter"] = not bool(git("status", "--porcelain"))
        if context["collectorExitCode"] != 0:
            raise RuntimeError("collector")
        if (not context["workingTreeCleanAfter"] or any(context[key + "Before"] != context[key + "After"]
                                                       for key in ("source", "binary", "harness"))):
            raise RuntimeError("provenance-changed")
        step("environment", [sys.executable, "scripts/performance_environment.py",
                             str(output / "fixtures.json"), str(output / "environment.json")], 30)
        context["status"] = "pass"
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        context["status"] = "fail"
        context["failure"] = str(error) if type(error) is RuntimeError else type(error).__name__
    finally:
        context["finishedAt"] = datetime.now(timezone.utc).isoformat()
        exclusive_json(output / "context.json", context)
    if context["status"] != "pass":
        description = "Long paragraph diagnostic" if paragraph_bytes is not None else "Large-file protocol"
        print(description + " failed; all partial evidence and generated fixtures are retained")
        return 1
    if paragraph_bytes is not None:
        print("Long paragraph diagnostic completed; evidence retained in build/logs/" + output.name)
        return 0
    result = execute([sys.executable, "scripts/summarize_large_open.py", str(output)],
                     output / "summary-validation.log", 30)
    print("Large-file protocol " + ("passed" if result == 0 else "summary validation failed") +
          "; evidence retained in build/logs/" + output.name)
    return result


if __name__ == "__main__":
    raise SystemExit(main())
