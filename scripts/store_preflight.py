#!/usr/bin/env python3
"""Verify delivery authorization before a job receives signing secrets."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from app_store_checks import require, tool_environment, validate_ci, validate_environment

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "Orbitane-Limited/NoteHush"


def github(path):
    # Delivery repeats this preflight after signing inputs reach the parent.
    # Grant gh only its workflow token, never the parent's other credentials or
    # an inherited host/config override. Missing tokens must not fall back to
    # the Mac's unrelated logged-in account.
    token = os.environ.get("GH_TOKEN", "")
    require(bool(token), "Missing GitHub workflow token")
    environment = {**tool_environment(), "GH_TOKEN": token}
    result = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/{path}"],
                            capture_output=True, check=False, env=environment, timeout=60)
    require(result.returncode == 0, "Unable to verify the required GitHub release gate")
    return json.loads(result.stdout)


def verify():
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "Unexpected delivery repository")
    require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and os.environ.get("GITHUB_REF") == "refs/heads/main", "Dispatch delivery from main")
    revision = os.environ.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[0-9a-f]{40}", revision), "Invalid release source commit")
    require(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT,
                                    env=tool_environment(), timeout=30).decode().strip() == revision,
            "Checkout differs from the dispatched source")
    require(not subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"],
                                        cwd=ROOT, env=tool_environment(), timeout=30),
            "Delivery source must be clean")
    require(github("git/ref/heads/main").get("object", {}).get("sha") == revision,
            "Main advanced; dispatch a new delivery from the reviewed current commit")
    run_id = os.environ.get("NOTEHUSH_CI_RUN_ID", "")
    require(re.fullmatch(r"[1-9]\d*", run_id), "Select a completed main CI run")
    validate_ci(github(f"actions/runs/{run_id}"), revision, REPOSITORY)
    validate_environment(github("environments/app-store"))
    return revision


if __name__ == "__main__":
    try:
        verify()
    except (ValueError, OSError, subprocess.SubprocessError, TypeError, KeyError):
        print("App Store preflight failed. Verify main CI and the protected signing environment.",
              file=sys.stderr)
        sys.exit(1)
    print("Exact main source, complete CI and environment protection verified.")
