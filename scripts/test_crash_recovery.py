#!/usr/bin/env python3
"""Kill a test-only writer around checkpoint publication and validate recovery."""
import selectors
import argparse
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def timed_drills(binary, mode, delays):
    for delay in delays:
        with tempfile.TemporaryDirectory(prefix="NoteHushCrashTests-") as directory:
            child = subprocess.Popen([str(binary), mode, directory], stdout=subprocess.PIPE)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(child.stdout, selectors.EVENT_READ)
                    if not selector.select(timeout=10):
                        raise RuntimeError("Writer did not acknowledge its first checkpoint")
                first = child.stdout.readline()
                if not first.strip().isdigit():
                    raise AssertionError("Writer exited without acknowledging a checkpoint")
                acknowledged = int(first)
                # Vary interruption timing intentionally; the test never assumes
                # an unacknowledged revision has been committed.
                time.sleep(delay)
                child.kill()
                remaining, _ = child.communicate(timeout=10)
                if child.returncode != -9:
                    raise AssertionError("Drill must end with SIGKILL, not normal termination")
                revisions = [int(line) for line in remaining.splitlines()]
                acknowledged = max([acknowledged, *revisions])
                result = subprocess.run([str(binary), "read", directory], check=True,
                                        text=True, capture_output=True, timeout=10)
                restored = int(result.stdout.strip())
                if restored < acknowledged:
                    raise AssertionError("Lost an acknowledged checkpoint")
                print(f"{mode} SIGKILL at {delay:.3f}s: "
                      f"acknowledged={acknowledged}, restored={restored}, intact")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=10)
                child.stdout.close()

def phase_drills(binary):
    phases = ("temporaryWritten", "fileSynchronized", "renamed", "directorySynchronized")
    count = 0
    for mode in ("first", "update", "clear", "migrate", "repair"):
        targets = ["blob", "backup", "primary"]
        if mode == "clear":
            targets += ["cleanup", "reclaim"]
        if mode == "repair":
            targets += ["evidenceBlob", "evidenceManifest"]
        for target in targets:
            target_phases = ("unlinked", "directorySynchronized") if target == "reclaim" else phases
            for phase in target_phases:
                with tempfile.TemporaryDirectory(prefix="NoteHushPhaseTests-") as directory:
                    child = subprocess.Popen(
                        [str(binary), "phase-write", directory, mode, target, phase],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                    try:
                        with selectors.DefaultSelector() as selector:
                            selector.register(child.stdout, selectors.EVENT_READ)
                            if not selector.select(timeout=10):
                                raise RuntimeError("Writer did not reach its publication phase")
                        if child.stdout.readline() != b"paused\n":
                            raise AssertionError("Writer exited without reaching the requested phase")
                        child.kill()
                        child.communicate(timeout=10)
                        if child.returncode != -9:
                            raise AssertionError("Drill must end with SIGKILL, not normal termination")
                        result = subprocess.run(
                            [str(binary), "phase-read", directory], check=True,
                            text=True, capture_output=True, timeout=10)
                        restored = int(result.stdout.strip())
                        installed = phase in ("renamed", "directorySynchronized")
                        if mode == "first":
                            expected = 0 if target == "blob" or (target == "backup" and not installed) else 1
                        else:
                            expected = 2 if target in ("cleanup", "reclaim") or (target == "primary" and installed) else 1
                        if restored != expected:
                            raise AssertionError(
                                f"Unexpected revision at {mode}/{target}/{phase}: {restored} != {expected}")
                        print(f"{mode}/{target}/{phase}: revision={restored}, "
                              "whole workspace and source bytes intact")
                        count += 1
                    finally:
                        if child.poll() is None:
                            child.kill()
                            child.wait(timeout=10)
                        child.stdin.close()
                        child.stdout.close()
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    configuration = parser.parse_args().configuration
    subprocess.run(["swift", "build", "--product", "RecoveryCrashHarness", "-c", configuration],
                   cwd=ROOT, check=True)
    binary = ROOT / f".build/{configuration}/RecoveryCrashHarness"
    timed_drills(binary, "write", [0, 0.001, 0.003, 0.006, 0.012, 0.02])
    timed_drills(binary, "continuous", [0, 0.015, 0.05])
    count = phase_drills(binary)
    if count != 74:
        raise AssertionError("Every configured publication phase must run")
    print(f"{9 + count} {configuration} crash recovery drills passed")


if __name__ == "__main__":
    main()
