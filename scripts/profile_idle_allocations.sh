#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${NOTEHUSH_EXCLUSIVE_INPUT:-}" != '1' ]]; then
  echo 'Establish exclusive input, idle CI, AC power and disk headroom before profiling.' >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo 'Commit the source before collecting accepted allocation evidence.' >&2
  exit 1
fi
built_revision="$(git rev-parse HEAD)"
mkdir -p build/logs
if [[ -e build/idle-resource.lock ]]; then
  echo 'An idle resource measurement is active or retained; inspect it first.' >&2
  exit 1
fi
if ! mkdir build/idle-allocation.lock; then
  echo 'Another allocation capture or interrupted lock requires inspection.' >&2
  exit 1
fi
# Preserve fixtures and partial traces after either success or failure.
trap 'rmdir build/idle-allocation.lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bash scripts/build_performance.sh
swift build -c release --product PerformanceFixtureHarness
fixture_harness="$(swift build -c release --show-bin-path)/PerformanceFixtureHarness"
application='build/PerformanceDerivedData/Build/Products/ReleasePerformance/NoteHushPerformance.app'
if [[ "$(git rev-parse HEAD)" != "$built_revision" || -n "$(git status --porcelain)" ]]; then
  echo 'Source changed during build; no fixture will be launched.' >&2
  exit 1
fi
run_directory="build/logs/Allocations-$(uuidgen)"
mkdir -m 700 "$run_directory"
manifest="$run_directory/fixtures.json"
"$fixture_harness" prepare-idle "$application" "$manifest"
python3 scripts/performance_environment.py "$manifest" "$run_directory/environment.json"
python3 scripts/verify_test_app.py "$application" --configuration ReleasePerformance
"$fixture_harness" profile-idle "$application" "$manifest" 2>&1 | tee "$run_directory/collection.log"
python3 scripts/verify_test_app.py "$application" --configuration ReleasePerformance
python3 - "$run_directory/environment.json" "$application" <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import sys

before = json.loads(Path(sys.argv[1]).read_text())
binary = Path(sys.argv[2]) / 'Contents/MacOS/NoteHushPerformance'
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip())
if (before['sourceRevision'] != revision or before['workingTreeDirty'] or dirty
        or before['binarySHA256'] != hashlib.sha256(binary.read_bytes()).hexdigest()):
    raise SystemExit('Source or binary provenance changed; preserve the unaccepted recording')
PY
printf '%s\n' "Allocation traces and fixture evidence retained in $run_directory."
