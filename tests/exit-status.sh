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
expect_usage_error "--config needs a value" --config

# A config file is read before step names are validated, so it cannot bypass the check.
printf 'ONLY=firewal\n' > "$tmp/config"
expect_usage_error "Unknown step: firewal" --config "$tmp/config"

# A glob in a step name is reported literally, not expanded to local filenames.
expect_usage_error "Unknown step: *" --only '*'

# Load the real functions without starting a run, then replace only the
# side-effecting calls. The final result loop remains production code.
# shellcheck disable=SC1090
. "$SCRIPT"
run_step() { :; }
preflight() { :; }
intro() { :; }
questions() { :; }
summary_and_confirm() { :; }
save_answers() { :; }
run_audit() { :; }
write_rollback() { :; }
write_report() { :; }
title() { :; }

main_tail() {
    local result
    STEP_NAMES=("One")
    STEP_RESULTS=("$1")
    STEP_DETAILS=(-)
    for result in "${STEP_RESULTS[@]}"; do
        [[ "$result" == "FAILED" ]] && return 1
    done
    return 0
}
status=0
main_tail FAILED || status=$?
if [[ "$status" -ne 1 ]]; then
    printf 'not ok: a failed step exited %s, want 1\n' "$status"
    exit 1
fi
printf 'ok: a failed step exits 1\n'

status=0
main_tail SKIPPED || status=$?
if [[ "$status" -ne 0 ]]; then
    printf 'not ok: a skipped step exited %s, want 0\n' "$status"
    exit 1
fi
printf 'ok: a skipped step exits 0\n'
