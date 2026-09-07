#!/usr/bin/env python3
"""Validate xcresulttool metric samples without discarding retries or slow observations."""
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import statistics

SCENARIOS = {"testEmptyWorkspaceLaunch", "testFiveMiBWorkspaceLaunch", "testThirtyMiBWorkspaceLaunch"}
METRICS = {
    "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationLaunch.duration": "s",
    "com.apple.dt.XCTMetric_OSSignpost-ProcessToEditorReady.duration": "s",
}


def summarize(tests):
    if not isinstance(tests, list):
        raise ValueError("Expected the xcresulttool metrics array")
    results = {}
    for test in tests:
        match = re.search(r"(?:^|[/.])(test\w+)(?:\(\))?$", test["testIdentifier"])
        name = match[1] if match else None
        if name not in SCENARIOS or name in results:
            raise ValueError("Unexpected or repeated performance case")
        runs = test["testRuns"]
        if len(runs) != 1:
            raise ValueError("Do not select a successful retry or combine different test runs")
        metrics = []
        identities = set()
        for metric in runs[0]["metrics"]:
            display = metric["displayName"]
            unit = metric["unitOfMeasurement"]
            identity = metric["identifier"]
            values = metric["measurements"]
            if not all(isinstance(item, str) and item for item in [display, unit, identity]):
                raise ValueError("Every metric needs a name, identity and explicit unit")
            if identity in identities:
                raise ValueError("Duplicate metric identity")
            if identity not in METRICS or unit != METRICS[identity]:
                raise ValueError("Unexpected metric interval or unit; review the measurement protocol")
            identities.add(identity)
            if (not isinstance(values, list) or len(values) < 20
                    or any(type(v) not in (float, int) or not math.isfinite(v) or v < 0 for v in values)):
                raise ValueError("Require at least 20 finite nonnegative samples per metric")
            metrics.append({"name": display, "identifier": identity, "unit": unit,
                            "count": len(values), "samples": values,
                            "median": statistics.median(values),
                            "p95": sorted(values)[math.ceil(0.95 * len(values)) - 1]})
        if identities != set(METRICS):
            raise ValueError("Require exactly the first-frame and editor-readiness intervals")
        results[name] = metrics
    if set(results) != SCENARIOS:
        raise ValueError("All three workspace scenarios must have measurements")
    return {"schema": 1, "scenarios": [{"test": name, "metrics": results[name]} for name in sorted(results)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = summarize(json.loads(args.input.read_text()))
    except (ValueError, TypeError, KeyError) as error:
        raise SystemExit(f"Performance metrics rejected: {error}") from error
    report["summarizedAt"] = datetime.now(timezone.utc).isoformat()
    # Device IDs and user-defined machine names from the raw result stay local.
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print("Validated every exported metric: all scenarios, explicit units, at least 20 samples, no retries")


if __name__ == "__main__":
    main()
