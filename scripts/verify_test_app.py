#!/usr/bin/env python3
"""Require the isolated test app to use exactly the product's sandbox entitlements."""
from pathlib import Path
import argparse
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--configuration", choices=("DebugUITesting", "ReleasePerformance"),
                        default="DebugUITesting")
    args = parser.parse_args()
    app = args.app.resolve()
    bundle_id = ("pk.codehub.NoteHush.PerformanceTesting" if args.configuration == "ReleasePerformance"
                 else "pk.codehub.NoteHush.UITesting")
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if (info.get("CFBundleIdentifier") != bundle_id
            or info.get("NoteHushRequiresTestWorkspace") != "YES"):
        raise SystemExit("Only the identified test app may run these sandbox checks")
    if args.configuration == "ReleasePerformance" and info.get("NoteHushPerformanceBuild") != "YES":
        raise SystemExit("Expected the optimized performance build identity")
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
    name = "performance-app-entitlements.plist" if args.configuration == "ReleasePerformance" else "test-app-entitlements.plist"
    (logs / name).write_bytes(result.stdout)
    print("Test app signature valid; sandbox entitlements exactly match the product")


if __name__ == "__main__":
    main()
