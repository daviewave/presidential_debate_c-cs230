#!/usr/bin/env bash
# Verifies a debate trace: every line is one of the five message templates,
# ids are 1..200, "attempting" ids are unique, each id's stages appear in
# template order with none skipped, the reconstructed lines in use never
# exceed 5 and operators in use never exceed 2 at any prefix, and the totals
# show the expected progress. The first violation is reported with its line
# number on stderr; success prints one summary line on stdout.
# Usage: check_trace.sh <trace file> <expected attempts> <min completed>
set -euo pipefail

MAX_ID=200
MAX_LINES_IN_USE=5
MAX_OPERATORS_IN_USE=2

fail() {
    echo "$1" >&2
    exit 1
}

require_three_arguments() {
    [ "$#" -eq 3 ] || fail "Usage: check_trace.sh <trace file> <expected attempts> <min completed>"
}

verify_the_trace() {
    local trace=$1 expected_attempts=$2 min_completed=$3
    awk -v expected="$expected_attempts" -v min_completed="$min_completed" \
        -v max_id="$MAX_ID" -v max_lines="$MAX_LINES_IN_USE" \
        -v max_operators="$MAX_OPERATORS_IN_USE" '
function complain(message) {
    print message | "cat 1>&2"
    close("cat 1>&2")
}
function fail(reason) {
    complain(sprintf("trace line %d: %s: %s", NR, reason, $0))
    failed = 1
    exit 1
}
function stage_of(rest) {
    if (rest == "is attempting to connect ...") return 1
    if (rest == "connects to an available line, call ringing ...") return 2
    if (rest == "is speaking to an operator.") return 3
    if (rest == "has proposed a question for candidates! The operator has left ...") return 4
    if (rest == "has hung up!") return 5
    return 0
}
{
    if (match($0, /^Thread [1-9][0-9]* /) == 0) fail("not a trace line")
    id = substr($0, 8, RLENGTH - 8) + 0
    stage = stage_of(substr($0, RLENGTH + 1))
    if (stage == 0) fail("unknown message")
    if (id < 1 || id > max_id) fail("id out of range")
    if (stage == 1 && (id in last)) fail("duplicate attempting id")
    if (last[id] + 0 != stage - 1) fail("stage out of order")
    last[id] = stage
    if (stage == 2) lines_in_use++
    if (stage == 5) lines_in_use--
    if (lines_in_use > max_lines) fail("more than " max_lines " lines in use")
    if (stage == 3) operators_in_use++
    if (stage == 4) operators_in_use--
    if (operators_in_use > max_operators) fail("more than " max_operators " operators in use")
    count[stage]++
}
END {
    if (failed) exit 1
    attempts = count[1] + 0
    completed = count[5] + 0
    if (attempts != expected + 0) {
        complain(sprintf("expected %d attempting lines, saw %d", expected, attempts))
        exit 1
    }
    if (completed < min_completed + 0) {
        complain(sprintf("expected at least %d completed calls, saw %d", min_completed, completed))
        exit 1
    }
    printf "trace ok: %d lines, %d attempts, %d completed\n", NR, attempts, completed
}' "$trace"
}

main() {
    require_three_arguments "$@"
    verify_the_trace "$1" "$2" "$3"
}

main "$@"
