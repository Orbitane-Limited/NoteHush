#!/usr/bin/env python3
"""Validate complete native file-opening evidence before reporting any aggregate."""
import argparse
import json
import math
from pathlib import Path
import re
import statistics
import uuid

WORKLOADS = ("ascii", "mixed")
COUNT = 20
BOUND = 10_000_000_000
HEADER = dict(kind="header", schema=1, unit="nanoseconds",
              boundary="fileOpenRequestToCompleteDurableCheckpoint",
              observationsPerWorkload=COUNT, bytesPerFile=10 * 1024 * 1024,
              observationBoundNanoseconds=BOUND, normalQuitBoundSeconds=20,
              workloads=list(WORKLOADS))
ORACLES = ("activeDuringObservation", "normalQuit", "completeRecovery",
           "unchangedSourceBytes", "fileBindingAndIdentity", "selectionAndViewport",
           "tabOrderAndWindow")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate evidence field")
        result[key] = value
    return result


def read_json(text):
    return json.loads(text, object_pairs_hook=unique_object,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite value")))


def require(condition):
    if not condition:
        raise ValueError("Incomplete or inconsistent large-file evidence")


def exact(record, expected):
    # Python considers True == 1. Evidence must retain the declared types.
    require(type(record) is dict and set(record) == set(expected))
    for key, value in expected.items():
        require(type(record[key]) is type(value) and record[key] == value)


def summarize(records, context):
    require(type(context) is dict and type(context.get("schema")) is int and context["schema"] == 1)
    for field in ("exclusiveInputAttested", "signatureBeforePassed", "signatureAfterPassed"):
        require(context.get(field) is True)
    require(context.get("status") == "pass" and type(context.get("collectorExitCode")) is int
            and context["collectorExitCode"] == 0)
    for field, length in (("source", 40), ("binary", 64), ("harness", 64)):
        before, after = context.get(field + "Before"), context.get(field + "After")
        require(type(before) is str and re.fullmatch(r"[0-9a-f]{%d}" % length, before)
                and before == after)
    require(context.get("workingTreeCleanBefore") is True
            and context.get("workingTreeCleanAfter") is True)
    require(type(records) is list and len(records) == 2 + len(WORKLOADS) * COUNT * 4)
    exact(records[0], HEADER)
    seen_workspaces, seen_processes = set(), set()
    cursor, results = 1, {}
    for workload in WORKLOADS:
        durations, returns = [], []
        for index in range(COUNT):
            attempt, process, observation, verification = records[cursor:cursor + 4]
            cursor += 4
            require(type(attempt) is dict and type(attempt.get("workspace")) is str)
            workspace = attempt["workspace"]
            require(str(uuid.UUID(workspace)).upper() == workspace and workspace not in seen_workspaces)
            seen_workspaces.add(workspace)
            exact(attempt, dict(kind="attempt", workload=workload, index=index, workspace=workspace))
            require(type(process) is dict and type(process.get("pid")) is int
                    and process["pid"] > 0 and process["pid"] not in seen_processes)
            seen_processes.add(process["pid"])
            exact(process, dict(kind="process", workload=workload, index=index,
                                pid=process["pid"], exactApplicationIdentity=True))
            require(type(observation) is dict)
            duration = observation.get("requestToCheckpointNanoseconds")
            returned = observation.get("launchServicesReturnNanoseconds")
            require(type(duration) is int and type(returned) is int
                    and 0 < returned <= duration <= BOUND)
            exact(observation, dict(kind="observation", workload=workload, index=index,
                                    requestToCheckpointNanoseconds=duration,
                                    launchServicesReturnNanoseconds=returned,
                                    withinObservationBound=True))
            exact(verification, dict(kind="verification", workload=workload, index=index,
                                     **{key: True for key in ORACLES}))
            durations.append(duration)
            returns.append(returned)
        ordered = sorted(durations)
        results[workload] = dict(count=COUNT, rawNanoseconds=durations,
                                 launchServicesReturnNanoseconds=returns,
                                 medianMilliseconds=statistics.median(ordered) / 1_000_000,
                                 p95Milliseconds=ordered[math.ceil(COUNT * .95) - 1] / 1_000_000)
    exact(records[cursor], dict(kind="finish", verifiedObservations=40))
    return dict(schema=1, boundary=HEADER["boundary"], workloads=results,
                sourceRevision=context["sourceBefore"], binarySHA256=context["binaryBefore"],
                harnessSHA256=context["harnessBefore"],
                limitations="Includes LaunchServices, recovery scheduling/I/O and independent host decoding. "
                "Warm filesystem caches; no physical-frame or interactive-window certification.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    args = parser.parse_args()
    records = [read_json(line) for line in (args.run / "observations.jsonl").read_text().splitlines()]
    result = summarize(records, read_json((args.run / "context.json").read_text()))
    with (args.run / "summary.json").open("x") as output:
        output.write(json.dumps(result, indent=2) + "\n")
    print("All 40 native file-opening observations and complete recovery checks verified")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError):
        raise SystemExit("Large-file evidence is incomplete, invalid, or its output already exists") from None
