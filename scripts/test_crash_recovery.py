#!/usr/bin/env python3
"""Kill a test-only writer around checkpoint publication and validate recovery."""
import selectors
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    subprocess.run(["swift", "build", "--product", "RecoveryCrashHarness"], cwd=ROOT, check=True)
    binary = ROOT / ".build/debug/RecoveryCrashHarness"
    for delay in [0, 0.001, 0.003, 0.006, 0.012, 0.02]:
        with tempfile.TemporaryDirectory(prefix="NoteHushCrashTests-") as directory:
            child = subprocess.Popen([str(binary), "write", directory], stdout=subprocess.PIPE)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(child.stdout, selectors.EVENT_READ)
                    if not selector.select(timeout=10):
                        raise RuntimeError("Writer did not acknowledge its first checkpoint")
                acknowledged = int(child.stdout.readline())
                # Vary interruption timing intentionally; the test never assumes
                # an unacknowledged revision has been committed.
                time.sleep(delay)
                child.kill()
                remaining, _ = child.communicate(timeout=10)
                revisions = [int(line) for line in remaining.splitlines()]
                acknowledged = max([acknowledged, *revisions])
                result = subprocess.run([str(binary), "read", directory], check=True,
                                        text=True, capture_output=True, timeout=10)
                restored = int(result.stdout.strip())
                if restored < acknowledged:
                    raise AssertionError("Lost an acknowledged checkpoint")
                print(f"SIGKILL at {delay:.3f}s: acknowledged={acknowledged}, restored={restored}, intact")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=10)
                child.stdout.close()
    print("6 crash recovery drills passed")


if __name__ == "__main__":
    main()
