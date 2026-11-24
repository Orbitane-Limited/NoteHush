#!/usr/bin/env python3
"""One bounded, generated Core Text reproduction; preserve every outcome."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).with_name("CoreTextLongProbe.swift")
NATIVE_PROCESSES = {"swift", "swiftc", "swift-frontend", "swift-build", "xcodebuild", "clang", "ld",
                    "xctest", "NoteHushPerformance", "NoteHushUITesting", "LongParagraphHarness"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bytes", type=int, choices=(262144, 1048576))
    parser.add_argument("variant", choices=("native", "rtl", "noLigatures", "forcedRTL", "bounded"))
    args = parser.parse_args()
    os.umask(0o077)
    output = ROOT / "build/logs" / ("CoreTextReproducer-" + str(uuid.uuid4()).upper())
    output.mkdir(parents=True, mode=0o700)
    environment = {key: os.environ[key] for key in
                   ("HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL") if key in os.environ}
    environment.update(PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
                       DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    result = {"schema": 1, "startedAt": datetime.now(timezone.utc).isoformat(), "bytes": args.bytes,
              "variant": args.variant, "timeoutSeconds": 10, "nativeCaseStarted": False,
              "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              "performanceAcceptance": False, "allEvidenceRetained": True}
    try:
        spec = importlib.util.spec_from_file_location("notehush_storage", ROOT / "scripts/check_runner_storage.py")
        if spec is None or spec.loader is None:
            raise RuntimeError("storageModuleUnavailable")
        storage = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(storage)
        capacities = [storage.inspect_capacity("workspace", ROOT),
                      storage.inspect_capacity("temporary", Path(environment.get("TMPDIR", "/tmp")))]
        result["storage"] = capacities
        if any(item["status"] != "pass" for item in capacities):
            raise RuntimeError("storagePreflightFailed")
        processes = subprocess.run(["/bin/ps", "-axo", "comm="], env=environment,
                                   capture_output=True, text=True, check=True, timeout=5)
        count = sum(Path(line.strip()).name in NATIVE_PROCESSES for line in processes.stdout.splitlines())
        result["nativeProcessesBeforeCompile"] = count
        if count:
            raise RuntimeError("competingNativeWork")
        copied = output / SOURCE.name
        shutil.copyfile(SOURCE, copied)
        with (output / "compile.log").open("xb") as log:
            compiled = subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                                       "-O", str(copied), "-o", str(output / "Probe")],
                                      env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=90)
        result["compileExitCode"] = compiled.returncode
        if compiled.returncode:
            raise RuntimeError("compileFailed")
        result["binarySHA256"] = hashlib.sha256((output / "Probe").read_bytes()).hexdigest()
        capacities = [storage.inspect_capacity("workspace", ROOT),
                      storage.inspect_capacity("temporary", Path(environment.get("TMPDIR", "/tmp")))]
        result["storageBeforeCase"] = capacities
        if any(item["status"] != "pass" for item in capacities):
            raise RuntimeError("storageBeforeCaseFailed")
        processes = subprocess.run(["/bin/ps", "-axo", "comm="], env=environment,
                                   capture_output=True, text=True, check=True, timeout=5)
        count = sum(Path(line.strip()).name in NATIVE_PROCESSES for line in processes.stdout.splitlines())
        result["nativeProcessesBeforeCase"] = count
        if count:
            raise RuntimeError("competingNativeWorkBeforeCase")
        with (output / "case.jsonl").open("xb") as log:
            child = subprocess.Popen([str(output / "Probe"), str(args.bytes), args.variant],
                                     env=environment, stdout=log, stderr=subprocess.STDOUT)
            result["nativeCaseStarted"] = True
            try:
                result["nativeExitCode"] = child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                result["nativeTimedOut"] = True
                child.kill()
                child.wait()
        result["caseRecords"] = []
        for line in (output / "case.jsonl").read_text().splitlines():
            try:
                result["caseRecords"].append(json.loads(line))
            except json.JSONDecodeError:
                result["unparsedOutputRetained"] = True
        result["typesetterCreated"] = any(row.get("kind") == "result" and
                                           row.get("createdTypesetter") is True
                                           for row in result["caseRecords"] if isinstance(row, dict))
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        result["preparationFailure"] = str(error) if type(error) is RuntimeError else type(error).__name__
    finally:
        result["finishedAt"] = datetime.now(timezone.utc).isoformat()
        with (output / "result.json").open("x") as report:
            json.dump(result, report, indent=2)
            report.write("\n")
    passed = (result.get("nativeExitCode") == 0 and result.get("typesetterCreated") is True
              and not result.get("nativeTimedOut") and "preparationFailure" not in result)
    print("Core Text typesetter reproduction " + ("completed" if passed else "did not succeed") +
          "; evidence retained under build/logs/" + output.name)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
