#!/usr/bin/env bash
# Runs a debate of the given length with stdout piped to a file, then asserts
# exit status 0, wall time within two seconds of the argument, and a trace with
# every caller attempting and at least <seconds> calls completed.
# Usage: debate.sh <seconds>
# Environment: PROGRAM (the binary; default build/presidential_debate).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROGRAM="${PROGRAM:-$REPO_DIR/build/presidential_debate}"
NUM_CALLS=200
GRACE_SECONDS=2
KILL_AFTER_SECONDS=10
TRACE="${TMPDIR:-/tmp}/presidential_debate_trace.$$"

status=0
elapsed=0

fail() {
    echo "$1" >&2
    exit 1
}

require_one_positive_integer_argument() {
    [ "$#" -eq 1 ] && [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail "Usage: debate.sh <seconds>"
}

remove_the_trace_however_this_ends() {
    trap 'rm -f "$TRACE"' EXIT
}

run_the_debate_into_the_trace() {
    local seconds=$1 started
    started=$(date +%s)
    if timeout "$((seconds + KILL_AFTER_SECONDS))" "$PROGRAM" "$seconds" > "$TRACE"; then
        status=0
    else
        status=$?
    fi
    elapsed=$(( $(date +%s) - started ))
}

exit_status_is_zero() {
    [ "$status" -eq 0 ]
}

finished_within_the_grace_period() {
    [ "$elapsed" -le "$(( $1 + GRACE_SECONDS ))" ]
}

require_a_clean_exit() {
    exit_status_is_zero || fail "debate ${1}s: exit status $status"
}

require_wall_time_near_the_debate_length() {
    finished_within_the_grace_period "$1" \
        || fail "debate ${1}s: took ${elapsed}s, limit $(( $1 + GRACE_SECONDS ))s"
}

check_the_trace() {
    "$SCRIPT_DIR/check_trace.sh" "$TRACE" "$NUM_CALLS" "$1"
}

report_the_debate() {
    echo "debate ${1}s: exit $status in ${elapsed}s"
}

main() {
    require_one_positive_integer_argument "$@"
    remove_the_trace_however_this_ends
    run_the_debate_into_the_trace "$1"
    require_a_clean_exit "$1"
    require_wall_time_near_the_debate_length "$1"
    check_the_trace "$1"
    report_the_debate "$1"
}

main "$@"
