#!/usr/bin/env python3
"""Record build/host provenance without user-defined device names or identifiers."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
from urllib.parse import unquote, urlparse


def command(*arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True).stdout.strip()


def power_summary(output):
    """Keep measurement conditions, not battery IDs or arbitrary device names."""
    source = re.search(r"Now drawing from '(AC Power|Battery Power|UPS Power)'(?:\n|$)", output)
    batteries = [line for line in output.splitlines() if re.match(r"\s*-InternalBattery-\d+\s", line)]
    line = batteries[0] if batteries else ""
    percentage = re.search(r"\b(\d{1,3})%;", line)
    percent = int(percentage[1]) if percentage and int(percentage[1]) <= 100 else None
    state = re.search(r"%;\s*(charged|charging|discharging|finishing charge)(?:;|$)", line)
    return {"source": source[1] if source else None, "batteryPercent": percent,
            "batteryState": state[1] if state else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    url = urlparse(manifest["applicationURL"])
    if manifest["version"] != 1 or url.scheme != "file" or url.netloc:
        raise SystemExit("Unexpected fixture manifest")
    app = Path(unquote(url.path))
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != "pk.codehub.NoteHush.PerformanceTesting"
            or info.get("NoteHushRequiresTestWorkspace") != "YES"
            or info.get("NoteHushPerformanceBuild") != "YES"
            or info.get("CFBundleExecutable") != "NoteHushPerformance"):
        raise SystemExit("Expected only the isolated performance build")
    report = {
        "schema": 1,
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "sourceRevision": command("git", "rev-parse", "HEAD"),
        "workingTreeDirty": bool(command("git", "status", "--porcelain")),
        "binarySHA256": hashlib.sha256((app / "Contents/MacOS/NoteHushPerformance").read_bytes()).hexdigest(),
        "marketingVersion": info["CFBundleShortVersionString"],
        "buildNumber": info["CFBundleVersion"],
        "hardwareModel": command("sysctl", "-n", "hw.model"),
        "memoryBytes": int(command("sysctl", "-n", "hw.memsize")),
        "logicalCPUs": int(command("sysctl", "-n", "hw.logicalcpu")),
        "architecture": command("uname", "-m"),
        "osVersion": command("sw_vers", "-productVersion"),
        "osBuild": command("sw_vers", "-buildVersion"),
        "xcode": command("xcodebuild", "-version"),
        "swift": command("swift", "--version"),
        "powerSource": power_summary(command("pmset", "-g", "batt")),
        "displayAndThermalAtFixturePreparation": manifest["environment"],
        "cacheConditions": ("One fresh process per scenario, then warmed repeated interactions and a final restart; warm filesystem caches."
                            if manifest["fixtures"][0]["name"] == "typingASCII" else
                            "Fresh processes; warm filesystem caches after host fixture preparation."),
        "otherGUIInputExclusivity": "Not automatically verified; operator must record this separately.",
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print("Recorded source, binary, hardware, toolchain, power, thermal and display provenance")


if __name__ == "__main__":
    main()
