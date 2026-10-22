from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import uuid

base = Path(__file__).resolve().parent
r = base / ("TextKitFragmentRangeProbe-" + str(uuid.uuid4()).upper())
os.umask(0o077)
r.mkdir(mode=0o700)
source = r / "TextKitFragmentRangeProbe.swift"
source.write_bytes((base / source.name).read_bytes())
(base / "latest-textkit-fragment-range-probe.json").write_text(json.dumps({"root": str(r)}, indent=2) + "\n")
env = {key: os.environ[key] for key in ("HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL") if key in os.environ}
env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
plan = {"kind": "Generated TextKit native/partial-fragment range diagnostic; unchanged full attributed source; no window or product policy change",
        "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "sizes": [16384, 262144, 1048576], "variants": ["native", "partial"],
        "oneObservationPerCell": True, "timeoutPerCellSeconds": 10,
        "notPerformanceAcceptance": True, "startedAt": datetime.datetime.now(datetime.timezone.utc).isoformat()}
(r / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
def require_readiness(stage):
    usage = shutil.disk_usage(base)
    native = subprocess.check_output(["/bin/ps", "-axo", "comm="], env=env, text=True)
    names = {"swift", "swift-frontend", "swiftc", "swift-build", "xcodebuild", "clang", "ld", "xctest", "NoteHushPerformance", "NoteHushUITesting", "LongParagraphHarness", "LayoutDiagnostic", "Probe"}
    count = sum(Path(line.strip()).name in names for line in native.splitlines())
    record = {"stage": stage, "freeBytes": usage.free, "requiredBytes": max(20 * 1024**3, (usage.total + 9) // 10), "nativeProcessCount": count}
    with (r / "readiness.jsonl").open("a") as journal:
        journal.write(json.dumps(record) + "\n")
    record["maintenancePending"] = (base / "notehush-native-maintenance.json").exists()
    if record["maintenancePending"] or count or usage.free < record["requiredBytes"]:
        (r / "preparation-stopped.json").write_text(json.dumps(record, indent=2) + "\n")
        raise SystemExit("Preparation paused; retained readiness evidence")

require_readiness("before-compile")
with (r / "compile.log").open("xb") as log:
    result = subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-O",
                             str(source), "-o", str(r / "Probe")], env=env, stdout=log,
                            stderr=subprocess.STDOUT, timeout=90).returncode
if result:
    print("Compiler failed; log retained", flush=True)
    raise SystemExit(1)
require_readiness("before-matrix")
results = []
for size in plan["sizes"]:
    for variant in plan["variants"]:
        name = str(size) + "-" + variant
        record = {"bytes": size, "variant": variant}
        with (r / (name + ".jsonl")).open("xb") as output:
            try:
                record["exitCode"] = subprocess.run([str(r / "Probe"), str(size), variant], env=env,
                                                     stdout=output, stderr=subprocess.STDOUT, timeout=10).returncode
            except subprocess.TimeoutExpired:
                record["timeout"] = True
        record["records"] = []
        for line in (r / (name + ".jsonl")).read_text().splitlines():
            try:
                record["records"].append(json.loads(line))
            except json.JSONDecodeError:
                record["unparsedOutputRetained"] = True
        results.append(record)
        print({"bytes": size, "variant": variant, "exitCode": record.get("exitCode"), "timeout": record.get("timeout", False), "phases": [x.get("phase") for x in record["records"]]}, flush=True)
plan["results"] = results
plan["binarySHA256"] = hashlib.sha256((r / "Probe").read_bytes()).hexdigest()
plan["finishedAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
(r / "result.json").write_text(json.dumps(plan, indent=2) + "\n")

controls = {row["variant"]: row for row in results if row["bytes"] == 16384}
def coverage(row):
    return next((r for r in row.get("records", []) if r.get("phase") == "coverage"), None)
a = coverage(controls["native"]); b = coverage(controls["partial"])
comparison = {"sizeBytes": 16384, "bothFullCoverage": bool(a and b and a.get("completeCoverage") and b.get("completeCoverage")),
              "sameNativeLineGeometry": bool(a and b and a.get("completeCoverage") and b.get("completeCoverage") and
                  [(line.get("globalStart"), line["length"], line.get("bounds")) for f in a["fragments"] for line in f.get("lines", [])] ==
                  [(line.get("globalStart"), line["length"], line.get("bounds")) for f in b["fragments"] for line in f.get("lines", [])]),
              "doesNotEstablishWholeAppEditingOrRendering": True}
(r / "control-comparison.json").write_text(json.dumps(comparison, indent=2) + "\n")
print(comparison, flush=True)
