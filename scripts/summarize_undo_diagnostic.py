#!/usr/bin/env python3
"""Validate a selected, UUID-isolated Undo trace without exposing unexpected contents."""
import argparse
import json
import math
import os
from pathlib import Path
import stat

MAX_BYTES = 256 * 1024
EVENTS = {"installed", "commandZ", "nextMainQueueTurn", "willUndo", "didUndo",
          "becameActive", "resignedActive", "shutdownRequested", "limitReached"}
STATES = {"noEditor", "original", "singleFirst", "singleLast", "caseSensitiveAll",
          "caseInsensitiveAll", "other"}
FLAGS = {"applicationActive", "workspaceKey", "editorFirstResponder",
         "firstResponderIsFieldEditor", "editorCanUndo", "editorIsUndoing"}
REQUIRED = FLAGS | {"sequence", "elapsedSeconds", "event", "fixtureState"}


def summarize(raw):
    if not raw or len(raw) > MAX_BYTES or not raw.endswith(b"\n"):
        raise ValueError("Empty, oversized or incomplete diagnostic artifact")
    try:
        records = [json.loads(line) for line in raw.splitlines()]
    except (ValueError, UnicodeError):
        raise ValueError("Malformed diagnostic record") from None
    if not 1 <= len(records) <= 256:
        raise ValueError("Unexpected diagnostic record count")
    previous = -1
    for index, record in enumerate(records):
        if not isinstance(record, dict) or not REQUIRED.issubset(record):
            raise ValueError("Missing diagnostic fields")
        if set(record) - REQUIRED - {"notificationFromEditor"}:
            raise ValueError("Unexpected diagnostic fields")
        if type(record["sequence"]) is not int or record["sequence"] != index:
            raise ValueError("Incomplete or reordered diagnostic sequence")
        elapsed = record["elapsedSeconds"]
        if (type(elapsed) not in (int, float) or not math.isfinite(elapsed)
                or elapsed < 0 or elapsed < previous):
            raise ValueError("Invalid diagnostic timing")
        previous = elapsed
        if any(type(record[key]) is not bool for key in FLAGS):
            raise ValueError("Invalid diagnostic flags")
        if record["event"] not in EVENTS or record["fixtureState"] not in STATES:
            raise ValueError("Unknown diagnostic classification")
        if "notificationFromEditor" in record and type(record["notificationFromEditor"]) is not bool:
            raise ValueError("Invalid Undo notification classification")
        if record["event"] in {"willUndo", "didUndo"} and "notificationFromEditor" not in record:
            raise ValueError("Missing Undo notification classification")
    if records[0]["event"] != "installed":
        raise ValueError("Missing diagnostic installation record")
    return {
        "schema": 1,
        "recordCount": len(records),
        "limitReached": any(row["event"] == "limitReached" for row in records),
        "shutdownObserved": any(row["event"] == "shutdownRequested" for row in records),
        "commandZCount": sum(row["event"] == "commandZ" for row in records),
        "editorUndoCount": sum(row["event"] == "didUndo" and row.get("notificationFromEditor") is True
                               for row in records),
        "otherUndoCount": sum(row["event"] == "didUndo" and row.get("notificationFromEditor") is False
                              for row in records),
        "observations": records,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        descriptor = os.open(args.trace, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
                raise ValueError("Expected a bounded regular diagnostic artifact")
            result = summarize(stream.read(MAX_BYTES + 1))
        with args.output.open("x") as stream:
            json.dump(result, stream, indent=2, allow_nan=False)
            stream.write("\n")
    except OSError:
        raise SystemExit("Could not read or retain the selected diagnostic artifact") from None
    except (ValueError, TypeError):
        raise SystemExit("Diagnostic artifact rejected; preserve the original for private inspection") from None
    print("Validated the selected diagnostic artifact; this does not establish a functional test pass")


if __name__ == "__main__":
    main()
