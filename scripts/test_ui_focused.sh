#!/usr/bin/env bash
# Incremental build + one UI test. Set VOICEFLOW_TEST_REBUILD=0 only when
# sources have not changed since the last successful build-for-testing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METHOD="${1:-testTranscriptModeToolbarToggleSwitchesMode}"
source "$ROOT/scripts/lib/simulator.sh"
source "$ROOT/scripts/lib/xcodebuild_test.sh"
voiceflow_simulator_prepare_destination "$ROOT"
voiceflow_xcodebuild_common_args \
  "$ROOT/src/VoiceFlow/VoiceFlow.xcodeproj" VoiceFlow \
  "$VOICEFLOW_TEST_DESTINATION" \
  "-only-testing:VoiceFlowUITests/VoiceFlowUITests/$METHOD"
if [[ "${VOICEFLOW_TEST_REBUILD:-1}" != 0 ]]; then
  started=$SECONDS
  voiceflow_xcodebuild_run build-for-testing
  printf 'Incremental build: %ss\n' "$((SECONDS-started))"
fi
shopt -s nullglob
runs=("$VOICEFLOW_DERIVED_DATA"/Build/Products/*.xctestrun)
if [[ ${#runs[@]} != 1 ]]; then
  printf 'Expected one .xctestrun in %s; found %s. Select a dedicated DerivedData path.\n' \
    "$VOICEFLOW_DERIVED_DATA/Build/Products" "${#runs[@]}" >&2
  exit 1
fi
started=$SECONDS
xcodebuild test-without-building \
  -xctestrun "${runs[0]}" \
  -derivedDataPath "$VOICEFLOW_DERIVED_DATA" \
  -destination "$VOICEFLOW_TEST_DESTINATION" \
  -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  "-only-testing:VoiceFlowUITests/VoiceFlowUITests/$METHOD"
printf 'Focused UI run: %ss\n' "$((SECONDS-started))"
