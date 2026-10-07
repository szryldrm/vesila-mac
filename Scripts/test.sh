#!/bin/bash
set -euo pipefail

# Runs Vesila's unit tests. Extra arguments are passed to `swift test` (e.g. --filter Presence).
#
# With only the Command Line Tools installed, the Swift Build backend doesn't hand the Swift
# Testing macro plugin to the compiler, and plain `swift test` fails with "plugin for module
# 'TestingMacros' not found". Passing the active toolchain's plugin directory works around it,
# and is harmless where it isn't needed.
#
# `swift test` can exit 0 when the test process ends before Swift Testing reports a result (for
# example, once AppKit stops the main run loop that Swift Testing's async entry point runs), so
# the run passes only on a final "Test run with ... passed" summary, without failures. Output is
# kept quiet and saved when a run does not pass; set VESILA_TEST_VERBOSE=1 to stream it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_BIN_DIR="$(dirname "$(xcrun --find swift)")"
TESTING_PLUGIN_DIR="$SWIFT_BIN_DIR/../lib/swift/host/plugins/testing"

PLUGIN_ARGS=()
if [ -d "$TESTING_PLUGIN_DIR" ]; then
  PLUGIN_ARGS=(-Xswiftc -plugin-path -Xswiftc "$(cd "$TESTING_PLUGIN_DIR" && pwd)")
fi

if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  BOLD=""
  DIM=""
  GREEN=""
  RED=""
  YELLOW=""
  CYAN=""
  RESET=""
fi

print_rule() {
  printf '%s\n' '────────────────────────────────────────────────────────────'
}

print_command() {
  printf '%s' "$DIM"
  printf '  '
  printf '%q ' "$@"
  printf '%s\n' "$RESET"
}

LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/vesila-tests.XXXXXX")"
KEEP_LOG=0
# EXIT alone: an INT or TERM trap would resume the script after removing the log, and an
# interrupted run still exits through this trap.
trap '[ "$KEEP_LOG" -eq 1 ] || rm -f "$LOG_FILE"' EXIT

COMMAND=(swift test --package-path "$ROOT_DIR")
if [ "${#PLUGIN_ARGS[@]}" -gt 0 ]; then
  COMMAND+=("${PLUGIN_ARGS[@]}")
fi
COMMAND+=("$@")

printf '\n%s%sVesila Test Runner%s\n' "$BOLD" "$CYAN" "$RESET"
print_rule
printf '%sProject:%s %s\n' "$BOLD" "$RESET" "$ROOT_DIR"
if [ "${#PLUGIN_ARGS[@]}" -gt 0 ]; then
  printf '%sSwift Testing plugin:%s detected\n' "$BOLD" "$RESET"
else
  printf '%sSwift Testing plugin:%s not needed / not found\n' "$BOLD" "$RESET"
fi
printf '%sCommand:%s\n' "$BOLD" "$RESET"
print_command "${COMMAND[@]}"
print_rule
printf '%sRunning tests...%s\n' "$BOLD" "$RESET"

set +e
if [ "${VESILA_TEST_VERBOSE:-0}" = "1" ]; then
  "${COMMAND[@]}" 2>&1 | tee "$LOG_FILE"
  TEST_EXIT_CODE=${PIPESTATUS[0]}
else
  "${COMMAND[@]}" >"$LOG_FILE" 2>&1
  TEST_EXIT_CODE=$?
fi
set -e

RUN_STARTED=0
if grep -qE 'Test run started\.' "$LOG_FILE"; then
  RUN_STARTED=1
fi

RUN_SUMMARY="$(grep -E 'Test run with .* (passed|failed)' "$LOG_FILE" | tail -n 1 || true)"
WARNINGS="$(grep -Ei '(^|[[:space:]])warning:' "$LOG_FILE" | awk '!seen[$0]++' || true)"
WARNING_COUNT=0
if [ -n "$WARNINGS" ]; then
  WARNING_COUNT="$(printf '%s\n' "$WARNINGS" | awk 'NF { count++ } END { print count + 0 }')"
fi

FAILURE_MARKERS="$(grep -E '^✘ (Test|Suite|Test run)' "$LOG_FILE" || true)"
# Not "Expectation failed" alone: a known issue's line ("recorded a known issue") carries it too.
ISSUE_MARKERS="$(grep -E 'recorded an issue' "$LOG_FILE" || true)"
FAILURE_COUNT=0
if [ -n "$FAILURE_MARKERS" ]; then
  FAILURE_COUNT="$(printf '%s\n' "$FAILURE_MARKERS" | awk 'NF { count++ } END { print count + 0 }')"
fi

FAILED_TEST_GROUPS="$(printf '%s\n' "$FAILURE_MARKERS" | grep -E '^✘ Test ' | grep -vE '^✘ Test run( |$)' | sed -E 's/^✘ Test ([^ ]+).*/\1/' | awk '!seen[$0]++' || true)"
FAILED_TEST_GROUP_COUNT=0
if [ -n "$FAILED_TEST_GROUPS" ]; then
  FAILED_TEST_GROUP_COUNT="$(printf '%s\n' "$FAILED_TEST_GROUPS" | awk 'NF { count++ } END { print count + 0 }')"
fi

UNFINISHED_SUITES="$(awk '
  /^◇ Suite / {
    name = $0
    sub(/^◇ Suite /, "", name)
    sub(/ started\.$/, "", name)
    if (!started[name]++) {
      order[++count] = name
    }
    next
  }
  /^✔ Suite / {
    name = $0
    sub(/^✔ Suite /, "", name)
    sub(/ (passed|failed)( after.*)?\.$/, "", name)
    finished[name] = 1
    next
  }
  /^✘ Suite / {
    name = $0
    sub(/^✘ Suite /, "", name)
    sub(/ (passed|failed)( after.*)?\.$/, "", name)
    finished[name] = 1
  }
  END {
    for (i = 1; i <= count; i++) {
      name = order[i]
      if (!finished[name]) {
        print name
      }
    }
  }
' "$LOG_FILE" || true)"
UNFINISHED_SUITE_COUNT=0
if [ -n "$UNFINISHED_SUITES" ]; then
  UNFINISHED_SUITE_COUNT="$(printf '%s\n' "$UNFINISHED_SUITES" | awk 'NF { count++ } END { print count + 0 }')"
fi

HAS_TEST_FAILURE=0
if [ "$FAILURE_COUNT" -gt 0 ] || [ -n "$ISSUE_MARKERS" ] || printf '%s\n' "$RUN_SUMMARY" | grep -q ' failed'; then
  HAS_TEST_FAILURE=1
fi

BUILD_FAILURE=0
if [ "$RUN_STARTED" -eq 0 ] && [ "$TEST_EXIT_CODE" -ne 0 ]; then
  BUILD_FAILURE=1
fi

RUN_INCOMPLETE=0
if [ "$RUN_STARTED" -eq 1 ] && [ -z "$RUN_SUMMARY" ] && [ "$HAS_TEST_FAILURE" -eq 0 ]; then
  RUN_INCOMPLETE=1
fi

# A filter that matches nothing makes swift test exit 0 without starting a Swift Testing run.
NO_TESTS_RAN=0
if { [ "$RUN_STARTED" -eq 0 ] && [ "$TEST_EXIT_CODE" -eq 0 ]; } \
  || printf '%s\n' "$RUN_SUMMARY" | grep -q 'Test run with 0 tests'; then
  NO_TESTS_RAN=1
fi

RESULT_KIND="pass"
if [ "$HAS_TEST_FAILURE" -eq 1 ]; then
  RESULT_KIND="test_failure"
elif [ "$BUILD_FAILURE" -eq 1 ]; then
  RESULT_KIND="build_failure"
elif [ "$RUN_INCOMPLETE" -eq 1 ]; then
  RESULT_KIND="incomplete"
elif [ "$TEST_EXIT_CODE" -ne 0 ]; then
  RESULT_KIND="runner_failure"
elif [ "$NO_TESTS_RAN" -eq 1 ]; then
  RESULT_KIND="no_tests"
elif ! printf '%s\n' "$RUN_SUMMARY" | grep -q ' passed'; then
  RESULT_KIND="incomplete"
fi

RESULT_EXIT_CODE="$TEST_EXIT_CODE"
if [ "$RESULT_KIND" != "pass" ] && [ "$RESULT_EXIT_CODE" -eq 0 ]; then
  RESULT_EXIT_CODE=1
fi

print_warnings() {
  if [ "$WARNING_COUNT" -gt 0 ]; then
    printf '\n%s%s⚠ WARNINGS (%s)%s\n' "$BOLD" "$YELLOW" "$WARNING_COUNT" "$RESET"
    printf '%s\n' "$WARNINGS"
  fi
}

print_failure_details() {
  awk '
    /^✘ Test run( |$)/ {
      in_failure = 0
      next
    }
    /^✘ Test / {
      count++
      line = $0
      sub(/^✘ Test /, "", line)

      test_name = line
      sub(/ .*/, "", test_name)

      printf "Failure #%d\n", count
      printf "  Test: %s\n", test_name

      issue = line
      sub(/^[^ ]+ recorded an issue/, "", issue)

      if (issue ~ /^ with [0-9]+ arguments? /) {
        case_details = issue
        sub(/^ with [0-9]+ arguments? /, "", case_details)
        sub(/ at [^ ]+:[0-9]+:[0-9]+:.*/, "", case_details)
        printf "  Case: %s\n", case_details
      }

      location = issue
      sub(/^.* at /, "", location)
      sub(/: (Expectation failed|Issue recorded|error:|Error:).*/, "", location)
      if (location != issue && location ~ /:[0-9]+:[0-9]+$/) {
        printf "  Location: %s\n", location
      }

      if (issue ~ /: Expectation failed:/) {
        expectation = issue
        sub(/^.*: Expectation failed: /, "", expectation)
        printf "  Reason: Expectation failed\n"
        printf "  Check: %s\n", expectation
      } else {
        reason = issue
        sub(/^ with [0-9]+ arguments? /, "", reason)
        sub(/^.* at [^ ]+:[0-9]+:[0-9]+: /, "", reason)
        if (reason != "") {
          printf "  Reason: %s\n", reason
        }
      }

      in_failure = 1
      details_header = 0
      next
    }
    in_failure && /^↳/ {
      detail = $0
      sub(/^↳[[:space:]]*/, "", detail)
      if (!details_header) {
        print "  Swift details:"
        details_header = 1
      }
      printf "    %s\n", detail
      next
    }
    {
      if (in_failure) {
        print ""
      }
      in_failure = 0
      details_header = 0
    }
  ' "$LOG_FILE" | tail -n 240
}

print_build_diagnostics() {
  grep -Ei 'error:|fatal error:|undefined symbols|linker command failed|compile command failed|emit-module command failed' "$LOG_FILE" \
    | awk '!seen[$0]++' \
    | tail -n 120 \
    || true
}

printf '\n'
print_rule
case "$RESULT_KIND" in
  pass)
    printf '%s%s✓ ALL TESTS PASSED%s\n' "$BOLD" "$GREEN" "$RESET"
    printf '%s\n' "$RUN_SUMMARY"
    print_warnings
    ;;

  test_failure)
    printf '%s%s✗ TESTS FAILED%s\n' "$BOLD" "$RED" "$RESET"
    printf '%sFailure type:%s Test assertion / Swift Testing failure\n' "$BOLD" "$RESET"
    printf '%sSwift exit code:%s %s\n' "$BOLD" "$RESET" "$TEST_EXIT_CODE"

    if [ -n "$RUN_SUMMARY" ]; then
      printf '%s\n' "$RUN_SUMMARY"
    fi

    if [ "$FAILED_TEST_GROUP_COUNT" -gt 0 ]; then
      printf '\n%s%sFailed test groups (%s)%s\n' "$BOLD" "$YELLOW" "$FAILED_TEST_GROUP_COUNT" "$RESET"
      printf '%s\n' "$FAILED_TEST_GROUPS" | sed 's/^/  • /'
    fi

    printf '\n%s%sWhy it failed%s\n' "$BOLD" "$YELLOW" "$RESET"
    DETAILS="$(print_failure_details)"
    if [ -n "$DETAILS" ]; then
      printf '%s\n' "$DETAILS"
    else
      DIAGNOSTICS="$(grep -Ei 'recorded an issue|Expectation failed|error:|fatal error:|failure:' "$LOG_FILE" | awk '!seen[$0]++' | tail -n 120 || true)"
      if [ -n "$DIAGNOSTICS" ]; then
        printf '%s\n' "$DIAGNOSTICS"
      else
        printf '%sSwift Testing reported a failure, but no assertion diagnostic could be isolated.%s\n' "$DIM" "$RESET"
      fi
    fi

    print_warnings
    ;;

  build_failure)
    printf '%s%s✗ BUILD / COMPILATION FAILED%s\n' "$BOLD" "$RED" "$RESET"
    printf '%sFailure type:%s Tests never started because build or compilation failed.\n' "$BOLD" "$RESET"
    printf '%sSwift exit code:%s %s\n' "$BOLD" "$RESET" "$TEST_EXIT_CODE"

    printf '\n%s%sWhy it failed%s\n' "$BOLD" "$YELLOW" "$RESET"
    DIAGNOSTICS="$(print_build_diagnostics)"
    if [ -n "$DIAGNOSTICS" ]; then
      printf '%s\n' "$DIAGNOSTICS"
    else
      printf '%sNo concise compiler/linker diagnostic could be isolated. Run verbose mode for the raw build output.%s\n' "$DIM" "$RESET"
    fi

    print_warnings
    ;;

  incomplete)
    printf '%s%s✗ TEST RUN INCOMPLETE%s\n' "$BOLD" "$RED" "$RESET"
    printf '%sFailure type:%s Test runner did not finish normally.\n' "$BOLD" "$RESET"
    printf '%sSwift exit code:%s %s\n' "$BOLD" "$RESET" "$TEST_EXIT_CODE"
    printf '\n%sWhat happened:%s\n' "$BOLD" "$RESET"
    printf '  Swift Testing started, but no final test summary was emitted.\n'
    printf '  No actual test assertion failure was reported.\n'
    printf '  This is different from a test expectation failing.\n'

    if [ "$UNFINISHED_SUITE_COUNT" -gt 0 ]; then
      printf '\n%s%sUnfinished suites (%s)%s\n' "$BOLD" "$YELLOW" "$UNFINISHED_SUITE_COUNT" "$RESET"
      printf '%s\n' "$UNFINISHED_SUITES" | sed 's/^/  • /'
    fi

    printf '\n%s%sLikely cause%s\n' "$BOLD" "$YELLOW" "$RESET"
    if [ "$TEST_EXIT_CODE" -eq 0 ]; then
      printf '  The Swift test process ended without emitting its normal final summary.\n'
      printf '  The visible completed tests may all be green, but the run cannot be trusted as complete.\n'
    else
      printf '  The Swift test process exited unexpectedly before the run completed.\n'
    fi

    print_warnings
    if [ "$WARNING_COUNT" -gt 0 ]; then
      printf '%sWarnings above are reported separately and were not classified as the test failure.%s\n' "$DIM" "$RESET"
    fi
    ;;

  runner_failure)
    printf '%s%s✗ TEST RUNNER FAILED%s\n' "$BOLD" "$RED" "$RESET"
    printf '%sFailure type:%s swift test exited with an error outside a normal completed test run.\n' "$BOLD" "$RESET"
    printf '%sSwift exit code:%s %s\n' "$BOLD" "$RESET" "$TEST_EXIT_CODE"

    printf '\n%s%sWhy it failed%s\n' "$BOLD" "$YELLOW" "$RESET"
    DIAGNOSTICS="$(grep -Ei 'error:|fatal error:|failure:|terminated|signal|crash' "$LOG_FILE" | awk '!seen[$0]++' | tail -n 120 || true)"
    if [ -n "$DIAGNOSTICS" ]; then
      printf '%s\n' "$DIAGNOSTICS"
    else
      printf '%sNo concise runner diagnostic could be isolated. Run verbose mode for the raw output.%s\n' "$DIM" "$RESET"
    fi

    print_warnings
    ;;

  no_tests)
    printf '%s%s✗ NO TESTS RAN%s\n' "$BOLD" "$RED" "$RESET"
    printf '%sFailure type:%s swift test finished without running any test.\n' "$BOLD" "$RESET"
    printf '%sSwift exit code:%s %s\n' "$BOLD" "$RESET" "$TEST_EXIT_CODE"
    printf '\n  Check that any --filter or --skip arguments match existing tests.\n'

    print_warnings
    ;;
esac

if [ "$RESULT_KIND" != "pass" ]; then
  KEEP_LOG=1
  printf '\n%sRaw Swift output:%s %s\n' "$BOLD" "$RESET" "$LOG_FILE"
  printf '%sTip:%s run with %sVESILA_TEST_VERBOSE=1 ./Scripts/test.sh%s to stream it while the tests run.\n' \
    "$BOLD" "$RESET" "$CYAN" "$RESET"
fi
print_rule
printf '\n'

exit "$RESULT_EXIT_CODE"
