#!/usr/bin/env python3
"""Read Apple's Automation Mode status before unattended XCTest UI work."""
import os
import re
import subprocess


STATUS = re.compile(
    r"Automation Mode is (enabled|disabled)\.\n"
    r"This device (requires|DOES NOT REQUIRE) user authentication to enable Automation Mode\.\n?"
)


def parse_status(output):
    match = STATUS.fullmatch(output)
    if match is None:
        raise ValueError("Unrecognized Automation Mode status; native UI tests were not started.")
    return match[1] == "enabled", match[2] == "requires"


def run_preflight():
    try:
        result = subprocess.run(
            ["/usr/bin/automationmodetool"], capture_output=True, text=True,
            timeout=5, check=True, env=dict(os.environ, LC_ALL="C"))
        if result.stderr.strip():
            raise ValueError("Automation Mode status returned a diagnostic; native UI tests were not started.")
        enabled, requires_authentication = parse_status(result.stdout)
    except (OSError, subprocess.SubprocessError, UnicodeError, ValueError):
        print("Could not verify Automation Mode. Inspect the host before starting native UI tests.")
        return 1
    if not enabled and requires_authentication:
        print("Native UI tests cannot start unattended: Automation Mode is disabled and requires administrator authentication.")
        print("The Mac owner can configure unattended testing with: sudo /usr/bin/automationmodetool enable-automationmode-without-authentication")
        print("This preflight only reads status; it never changes authentication or grants accessibility access.")
        return 1
    print("Automation Mode preflight passed. An awake, unlocked desktop and exclusive input are still required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(run_preflight())
