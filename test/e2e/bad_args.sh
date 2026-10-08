#!/usr/bin/env bash
# Every bad argument set (none, 0, -3, abc, 3x, two arguments) must make the
# program exit non-zero with a "Usage: " line on stderr and nothing on stdout.
# Usage: bad_args.sh
# Environment: PROGRAM (the binary; default build/presidential_debate).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROGRAM="${PROGRAM:-$REPO_DIR/build/presidential_debate}"
KILL_AFTER_SECONDS=5
STDOUT_CAPTURE="${TMPDIR:-/tmp}/presidential_debate_stdout.$$"
STDERR_CAPTURE="${TMPDIR:-/tmp}/presidential_debate_stderr.$$"

status=0

fail() {
    echo "$1" >&2
    exit 1
}

remove_the_captures_however_this_ends() {
    trap 'rm -f "$STDOUT_CAPTURE" "$STDERR_CAPTURE"' EXIT
}

run_the_program_with() {
    if timeout "$KILL_AFTER_SECONDS" "$PROGRAM" "$@" > "$STDOUT_CAPTURE" 2> "$STDERR_CAPTURE"; then
        status=0
    else
        status=$?
    fi
}

exit_status_is_nonzero() {
    [ "$status" -ne 0 ]
}

stdout_is_empty() {
    [ ! -s "$STDOUT_CAPTURE" ]
}

stderr_has_a_usage_line() {
    grep -q '^Usage: ' "$STDERR_CAPTURE"
}

expect_rejection_of() {
    local label="arguments '${*:-<none>}'"
    run_the_program_with "$@"
    exit_status_is_nonzero || fail "$label: exit status 0"
    stdout_is_empty || fail "$label: stdout not empty"
    stderr_has_a_usage_line || fail "$label: no usage line on stderr"
}

reject_each_bad_argument_set() {
    expect_rejection_of
    expect_rejection_of 0
    expect_rejection_of -3
    expect_rejection_of abc
    expect_rejection_of 3x
    expect_rejection_of 1 2
}

report_success() {
    echo "bad arguments rejected"
}

main() {
    remove_the_captures_however_this_ends
    reject_each_bad_argument_set
    report_success
}

main "$@"
