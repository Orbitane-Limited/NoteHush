#!/usr/bin/env python3
"""Validate the optimized isolated app settings before a performance launch."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def validate(settings, scheme):
    matches = [entry["buildSettings"] for entry in settings if entry.get("target") == "NoteHush"]
    if len(matches) != 1:
        raise ValueError("Expected exactly one NoteHush build-settings record")
    actual = matches[0]
    required = {
        "CONFIGURATION": "ReleasePerformance",
        "PRODUCT_BUNDLE_IDENTIFIER": "pk.codehub.NoteHush.PerformanceTesting",
        "EXECUTABLE_NAME": "NoteHushPerformance",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "NOTEHUSH_TEST_WORKSPACE_REQUIRED": "YES",
        "NOTEHUSH_PERFORMANCE_BUILD": "YES",
        "ENABLE_HARDENED_RUNTIME": "YES",
    }
    if any(actual.get(key) != value for key, value in required.items()):
        raise ValueError("The app is not the expected optimized isolated build")
    flags = set(actual.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split())
    if not {"NOTEHUSH_REQUIRE_TEST_WORKSPACE", "NOTEHUSH_PERFORMANCE_TESTING"} <= flags or "DEBUG" in flags:
        raise ValueError("Unexpected performance compilation conditions")
    for action in ["TestAction", "LaunchAction", "ProfileAction", "ArchiveAction", "AnalyzeAction"]:
        item = scheme.find(action)
        if item is None or item.get("buildConfiguration") != "ReleasePerformance":
            raise ValueError("A performance scheme action could select the shipping workspace")
    for action in ["TestAction", "LaunchAction"]:
        if scheme.find(action).get("selectedDebuggerIdentifier"):
            raise ValueError("Performance samples must not run under the debugger")
    return required


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("settings", type=Path)
    args = parser.parse_args()
    scheme = ET.parse(ROOT / "NoteHush.xcodeproj/xcshareddata/xcschemes/NoteHushPerformance.xcscheme").getroot()
    try:
        validate(json.loads(args.settings.read_text()), scheme)
    except (ValueError, KeyError, TypeError) as error:
        raise SystemExit(str(error)) from error
    print("Performance configuration valid: optimized, isolated workspace, debugger disabled")


if __name__ == "__main__":
    main()
