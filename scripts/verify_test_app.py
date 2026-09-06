#!/usr/bin/env python3
"""Require the isolated test app to use exactly the product's sandbox entitlements."""
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Expected the built DebugUITesting app")
    app = Path(sys.argv[1]).resolve()
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if (info.get("CFBundleIdentifier") != "pk.codehub.NoteHush.UITesting"
            or info.get("NoteHushRequiresTestWorkspace") != "YES"):
        raise SystemExit("Only the identified test app may run these sandbox checks")
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    result = subprocess.run(["codesign", "--display", "--entitlements", "-", "--xml", str(app)],
                            check=True, capture_output=True)
    actual = plistlib.loads(result.stdout)
    with (ROOT / "Config/NoteHush.entitlements").open("rb") as stream:
        expected = plistlib.load(stream)
    if actual != expected:
        raise SystemExit("Test app entitlements differ from the product; injected exceptions are not allowed")
    logs = ROOT / "build/logs"
    logs.mkdir(parents=True, exist_ok=True)
    (logs / "test-app-entitlements.plist").write_bytes(result.stdout)
    print("Test app signature valid; sandbox entitlements exactly match the product")


if __name__ == "__main__":
    main()
