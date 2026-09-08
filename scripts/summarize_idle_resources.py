#!/usr/bin/env python3
"""Validate both complete isolated idle recordings; retain all observations."""
import argparse
import json
import math
import os
from pathlib import Path
import stat
import statistics

MAX_BYTES = 128 * 1024
SCENARIOS = ("empty", "fiveMiB")
HEADER = {"record": "header", "schema": 1, "api": "proc_pid_rusage/RUSAGE_INFO_V0",
          "clock": "ContinuousClock", "cpuUnit": "mach ticks", "memoryUnit": "bytes",
          "settlingSeconds": 30, "plannedIntervals": 60, "intervalSeconds": 1}
NUMBERS = {"index", "elapsedBeforeReadNanoseconds", "elapsedAfterReadNanoseconds",
           "userTimeMachTicks", "systemTimeMachTicks", "residentBytes", "physicalFootprintBytes"}
FINISH = {"record": "finish", "normalTermination": True, "exactFixtureVerification": True}


def exact_fields(actual, expected):
    return (type(actual) is dict and actual.keys() == expected.keys()
            and all(type(actual[key]) is type(value) and actual[key] == value
                    for key, value in expected.items()))


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate metric field")
        result[key] = value
    return result


def decode(raw):
    if not raw or len(raw) > MAX_BYTES or not raw.endswith(b"\n"):
        raise ValueError("Empty, oversized or partial recording")
    try:
        records = [json.loads(line, object_pairs_hook=reject_duplicates) for line in raw.splitlines()]
    except (ValueError, UnicodeError):
        raise ValueError("Malformed recording") from None
    if len(records) != 63 or type(records[0]) is not dict:
        raise ValueError("Expected header, 61 observations and verified finish")
    scenario = records[0].get("scenario")
    numerator = records[0].get("machTimebaseNumerator")
    denominator = records[0].get("machTimebaseDenominator")
    if any(type(value) is not int or not 0 < value <= 2**32 - 1 for value in (numerator, denominator)):
        raise ValueError("Invalid Mach timebase conversion")
    if scenario not in SCENARIOS or not exact_fields(records[0], dict(
            HEADER, scenario=scenario, machTimebaseNumerator=numerator, machTimebaseDenominator=denominator)):
        raise ValueError("Unexpected scenario, timing protocol or metric units")
    if not exact_fields(records[-1], FINISH):
        raise ValueError("Missing normal termination or exact fixture verification")
    samples = records[1:-1]
    previous = None
    for index, sample in enumerate(samples):
        if type(sample) is not dict or sample.keys() != NUMBERS | {"record", "applicationActive"}:
            raise ValueError("Unexpected observation fields")
        if sample["record"] != "sample" or sample["applicationActive"] is not True:
            raise ValueError("Inactive application or invalid observation")
        if any(type(sample[key]) is not int or not 0 <= sample[key] <= 2**64 - 1 for key in NUMBERS):
            raise ValueError("Invalid numeric observation")
        if sample["index"] != index or not sample["residentBytes"] or not sample["physicalFootprintBytes"]:
            raise ValueError("Missing observation or unavailable memory counter")
        start, end = sample["elapsedBeforeReadNanoseconds"], sample["elapsedAfterReadNanoseconds"]
        if start > end or end >= 600_000_000_000:
            raise ValueError("Invalid counter read bounds")
        if previous is not None:
            if start < previous["elapsedAfterReadNanoseconds"] + 1_000_000_000:
                raise ValueError("Nonmonotonic or shortened observation interval")
            if any(sample[key] < previous[key] for key in ("userTimeMachTicks", "systemTimeMachTicks")):
                raise ValueError("CPU counter reset or process change")
        previous = sample
    first, last = samples[0], samples[-1]
    minimum_elapsed = last["elapsedBeforeReadNanoseconds"] - first["elapsedAfterReadNanoseconds"]
    maximum_elapsed = last["elapsedAfterReadNanoseconds"] - first["elapsedBeforeReadNanoseconds"]
    elapsed = (minimum_elapsed + maximum_elapsed) / 2
    if minimum_elapsed < 60_000_000_000:
        raise ValueError("Observation window is shorter than 60 seconds")
    cpu_ticks = sum(last[key] - first[key] for key in ("userTimeMachTicks", "systemTimeMachTicks"))
    cpu = cpu_ticks * numerator / denominator
    intervals = []
    for left, right in zip(samples, samples[1:]):
        duration = ((right["elapsedBeforeReadNanoseconds"] + right["elapsedAfterReadNanoseconds"])
                    - (left["elapsedBeforeReadNanoseconds"] + left["elapsedAfterReadNanoseconds"])) / 2
        used = (sum(right[key] - left[key] for key in ("userTimeMachTicks", "systemTimeMachTicks"))
                * numerator / denominator)
        intervals.append(100 * used / duration)

    def memory_summary(key):
        values = [row[key] for row in samples]
        return {"minimumBytes": min(values), "medianBytes": statistics.median(values),
                "p95Bytes": sorted(values)[math.ceil(0.95 * len(values)) - 1],
                "maximumBytes": max(values), "finalBytes": values[-1]}

    return {"scenario": scenario, "sampleCount": len(samples), "elapsedNanoseconds": elapsed,
            "cpuTimeMachTicks": cpu_ticks, "machTimebaseNumerator": numerator,
            "machTimebaseDenominator": denominator,
            "elapsedLowerBoundNanoseconds": minimum_elapsed, "elapsedUpperBoundNanoseconds": maximum_elapsed,
            "cpuTimeNanoseconds": cpu, "averageCPUPercentOfOneCore": 100 * cpu / elapsed,
            "cpuPercentLowerBound": 100 * cpu / maximum_elapsed,
            "cpuPercentUpperBound": 100 * cpu / minimum_elapsed,
            "intervalCPUPercentOfOneCore": intervals, "resident": memory_summary("residentBytes"),
            "physicalFootprint": memory_summary("physicalFootprintBytes"), "observations": samples}


def summarize(raw_recordings):
    results = [decode(raw) for raw in raw_recordings]
    if len(results) != 2 or tuple(row["scenario"] for row in results) != SCENARIOS:
        raise ValueError("Expected both scenarios exactly once in declared order")
    if any(results[0][field] != results[1][field]
           for field in ("machTimebaseNumerator", "machTimebaseDenominator")):
        raise ValueError("Inconsistent clock provenance between scenarios")
    return {"schema": 1, "measurement": "App-only settled CPU, RSS and physical footprint",
            "cpuConvention": "100 percent is one fully occupied logical core; no machine-core division",
            "energyMeasured": False, "independentRunsPerScenario": 1,
            "results": results,
            "limitations": ["One 60-second window per workload, not 20 independent process runs",
                            "Fixed settling interval does not guarantee deferred work completed",
                            "No hardware-independent budget pass or physical energy measurement"]}


def read_recording(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_BYTES:
            raise ValueError("Expected bounded regular recording")
        return stream.read(MAX_BYTES + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = summarize([read_recording(args.directory / f"idle-{name}.jsonl") for name in SCENARIOS])
        with args.output.open("x") as stream:
            json.dump(result, stream, indent=2, allow_nan=False)
            stream.write("\n")
    except (OSError, ValueError, TypeError):
        raise SystemExit("Idle resource recording rejected; preserve all original evidence") from None
    print("Both complete idle recordings validated; no performance or energy acceptance implied")


if __name__ == "__main__":
    main()
