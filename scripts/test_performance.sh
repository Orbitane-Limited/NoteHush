#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_runner_storage.py
python3 scripts/check_ui_automation.py
mkdir -p build/logs
derived="build/PerformanceDerivedData"
application="$derived/Build/Products/ReleasePerformance/NoteHushPerformance.app"
destination="platform=macOS,arch=$(uname -m)"
bash scripts/build_performance.sh
swift build --product PerformanceFixtureHarness
fixture_harness="$(swift build --show-bin-path)/PerformanceFixtureHarness"
python3 scripts/check_runner_storage.py
python3 scripts/check_ui_automation.py
manifest="build/performance-fixtures.json"
# The host helper creates the fixture manifest without replacing existing evidence.
# Never clean up a prior run merely because this run could not acquire ownership.
"$fixture_harness" prepare "$application" "$manifest"
cleanup() { "$fixture_harness" cleanup "$application" "$manifest"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
result="build/logs/Performance-$(uuidgen).xcresult"
python3 scripts/performance_environment.py "$manifest" "${result%.xcresult}-environment.json"
# These opt-in tests perform 20 full launches per case. Their allowance does not
# change the functional CI suite's 30/60-second per-case limits.
xcodebuild -project NoteHush.xcodeproj -scheme NoteHushPerformance -configuration ReleasePerformance \
  -destination "$destination" -derivedDataPath "$derived" -resultBundlePath "$result" \
  -only-testing:NoteHushPerformanceTests/LaunchPerformanceTests \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600 \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test-without-building 2>&1 | tee build/logs/performance-tests.log
python3 scripts/verify_test_app.py "$application" --configuration ReleasePerformance
"$fixture_harness" verify "$application" "$manifest"
xcrun xcresulttool export metrics --path "$result" --output-path "${result%.xcresult}-metrics"
xcrun xcresulttool get test-results metrics --path "$result" > "${result%.xcresult}-raw.json"
python3 scripts/summarize_performance.py "${result%.xcresult}-raw.json" "${result%.xcresult}-summary.json"
