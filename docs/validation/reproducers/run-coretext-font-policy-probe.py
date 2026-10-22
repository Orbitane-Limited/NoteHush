from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import uuid

base = Path(__file__).resolve().parent
r = base / ("CoreTextFontPolicyProbe-" + str(uuid.uuid4()).upper())
os.umask(0o077)
r.mkdir(mode=0o700)
source = r / "CoreTextFontPolicyProbe.swift"
source.write_bytes((base / source.name).read_bytes())
(base / "latest-coretext-font-policy-probe.json").write_text(json.dumps({"root": str(r)}, indent=2) + "\n")
env = {key: os.environ[key] for key in ("HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL") if key in os.environ}
env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
plan = {"kind": "Separate generated native font-fixing/font-base/single-script controls; no app window or product policy change",
        "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "sizes": [262144, 1048576], "variants": ["fixFonts", "arabicBase", "arabicOnly", "emojiOnly"],
        "oneObservationPerCell": True, "timeoutPerCellSeconds": 10,
        "notPerformanceAcceptance": True, "startedAt": datetime.datetime.now(datetime.timezone.utc).isoformat()}
(r / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
def require_readiness(stage):
    usage = shutil.disk_usage(base)
    native = subprocess.check_output(["/bin/ps", "-axo", "comm="], env=env, text=True)
    names = {"swift", "swift-frontend", "swiftc", "swift-build", "xcodebuild", "clang", "ld", "xctest", "NoteHushPerformance", "NoteHushUITesting", "LongParagraphHarness", "LayoutDiagnostic"}
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
        print(record, flush=True)
plan["results"] = results
plan["binarySHA256"] = hashlib.sha256((r / "Probe").read_bytes()).hexdigest()
plan["finishedAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
(r / "result.json").write_text(json.dumps(plan, indent=2) + "\n")
