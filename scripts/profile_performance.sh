#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_runner_storage.py
source scripts/performance_fixture_exit.sh
bash scripts/build_performance.sh
swift build --product PerformanceFixtureHarness
fixture_harness="$(swift build --show-bin-path)/PerformanceFixtureHarness"
python3 scripts/check_runner_storage.py
application="build/PerformanceDerivedData/Build/Products/ReleasePerformance/NoteHushPerformance.app"
manifest="build/performance-fixtures.json"
"$fixture_harness" prepare "$application" "$manifest"
trap 'performance_fixture_exit "$?" "$fixture_harness" cleanup "$application" "$manifest"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 scripts/performance_environment.py "$manifest" "build/logs/profile-environment-$(uuidgen).json"
"$fixture_harness" profile "$application" "$manifest" 2>&1 | tee build/logs/performance-profile.log
python3 scripts/verify_test_app.py "$application" --configuration ReleasePerformance
