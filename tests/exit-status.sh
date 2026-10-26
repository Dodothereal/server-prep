#!/usr/bin/env bash
# shellcheck disable=SC2034
# Tests server-prep.sh's final status and argument validation without changing the host.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/server-prep.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expect_usage_error() {   # expect_usage_error "MESSAGE" ARGS...
    local want="$1" out status=0
    shift
    out="$("$SCRIPT" "$@" 2>&1)" || status=$?
    if [[ "$status" -ne 2 || "$out" != *"$want"* ]]; then
        printf 'not ok: %s exited %s, want 2 and "%s"\n' "$*" "$status" "$want"
        exit 1
    fi
    printf 'ok: %s exits 2\n' "$*"
}
expect_usage_error "Unknown step: firewal" --only firewal
expect_usage_error "Unknown step: bogus" --skip ssh,bogus
expect_usage_error "--only needs a value" --only
expect_usage_error "--skip needs a value" --skip
expect_usage_error "--config needs a value" --config

# A config file is read before step names are validated, so it cannot bypass the check.
printf 'ONLY=firewal\n' > "$tmp/config"
expect_usage_error "Unknown step: firewal" --config "$tmp/config"

# A glob in a step name is reported literally, not expanded to local filenames.
expect_usage_error "Unknown step: *" --only '*'

# stdin and bash -c have no BASH_SOURCE[0]. Help must not emit an unbound-variable
# error during initialization. These exit before main, so they cannot touch the host.
expect_help() {   # expect_help LABEL COMMAND...
    local label="$1" out status=0
    shift
    out="$("$@" 2>"$tmp/stderr")" || status=$?
    if [[ "$status" -ne 0 || "$out" != *"Exit codes:"* || -s "$tmp/stderr" ]]; then
        printf 'not ok: %s help exited %s or emitted an error\n' "$label" "$status"
        cat "$tmp/stderr" >&2
        exit 1
    fi
    printf 'ok: %s help exits 0 without errors\n' "$label"
}
expect_help stdin bash -s -- --help < "$SCRIPT"
expect_help 'bash -c' bash -c "$(cat "$SCRIPT")" server-prep.sh --help

# Load the real functions without starting a run, then replace the calls that
# touch the host. --yes also avoids requiring a terminal when sourcing in CI.
# shellcheck disable=SC1090
. "$SCRIPT" --yes
preflight() { :; }
intro() { :; }
questions() { :; }
summary_and_confirm() { :; }
save_answers() { :; }
run_audit() { :; }
write_rollback() { :; }
write_report() { :; }
title() { :; }

# Fake steps only record their result. main() and its final result loop are real.
OS_PRETTY="test"
run_step() {
    STEP_NAMES+=("$2")
    STEP_DETAILS+=(-)
    if [[ "$1" == "$FAIL_STEP" ]]; then
        STEP_RESULTS+=("FAILED")
    else
        STEP_RESULTS+=("$PASS_RESULT")
    fi
}

expect_main_status() {   # expect_main_status FAIL_STEP PASS_RESULT WANT
    local status=0
    STEP_NAMES=(); STEP_RESULTS=(); STEP_DETAILS=()
    FAIL_STEP="$1"
    PASS_RESULT="$2"
    main >"$tmp/main-output" 2>&1 || status=$?
    if [[ "$status" -ne "$3" || ${#STEP_RESULTS[@]} -eq 0 ]]; then
        printf 'not ok: main with failed step "%s" and other steps "%s" gave %s, want %s\n' "$1" "$2" "$status" "$3"
        cat "$tmp/main-output" >&2
        exit 1
    fi
    printf 'ok: main with failed step "%s" and other steps "%s" gives %s\n' "$1" "$2" "$3"
}
expect_main_status firewall 'OK (already)' 1   # failure before the final step
expect_main_status suid 'OK (already)' 1       # failure in the final step
expect_main_status none 'OK (already)' 0       # a missing return 0 must fail this
expect_main_status none SKIPPED 0             # no selected step failed
