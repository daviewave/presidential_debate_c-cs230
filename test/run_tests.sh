#!/usr/bin/env bash
# Builds and runs every unit test, then the end-to-end scripts.
# Usage: test/run_tests.sh [long]
#   default: bad-argument cases plus the 3 s and 10 s debates
#   long:    the 20 s, 50 s and 100 s debates (about three minutes)
# Environment: CC, TEST_CFLAGS (compiler and flags for the unit tests),
#              PROGRAM (the binary the e2e scripts run).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
UNIT_BUILD_DIR="$REPO_DIR/build/test"
DEFAULT_TEST_CFLAGS="-std=c99 -D_POSIX_C_SOURCE=200809L -pthread -Wall -Wextra -O0 -g3 -Wno-unused-function"
SHORT_DEBATES="3 10"
LONG_DEBATES="20 50 100"

CC="${CC:-gcc}"
TEST_CFLAGS="${TEST_CFLAGS:-$DEFAULT_TEST_CFLAGS}"
export PROGRAM="${PROGRAM:-$REPO_DIR/build/presidential_debate}"
failures=0

report() {
    local status=$1 name=$2
    if [ "$status" -eq 0 ]; then
        echo "PASS $name"
    else
        echo "FAIL $name"
        failures=$((failures + 1))
    fi
}

long_mode_requested() {
    [ "${1:-short}" = "long" ]
}

build_and_run_each_unit_test() {
    mkdir -p "$UNIT_BUILD_DIR"
    local source binary
    for source in "$SCRIPT_DIR"/unit/test_*.c; do
        [ -e "$source" ] || continue
        binary="$UNIT_BUILD_DIR/$(basename "${source%.c}")"
        # shellcheck disable=SC2086
        "$CC" $TEST_CFLAGS -o "$binary" "$source" -pthread
        if "$binary" >/dev/null; then
            report 0 "$binary"
        else
            report 1 "$binary"
        fi
    done
}

run_e2e() {
    local script=$1
    shift
    if "$SCRIPT_DIR/e2e/$script" "$@" >/dev/null; then
        report 0 "$script $*"
    else
        report 1 "$script $*"
    fi
}

run_each_debate_of() {
    local seconds
    for seconds in $1; do
        run_e2e debate.sh "$seconds"
    done
}

run_the_short_e2e_suite() {
    run_e2e bad_args.sh
    run_each_debate_of "$SHORT_DEBATES"
}

run_the_long_e2e_suite() {
    run_each_debate_of "$LONG_DEBATES"
}

summarise_and_exit() {
    echo "$failures failure(s)"
    exit $((failures > 0))
}

main() {
    build_and_run_each_unit_test
    if long_mode_requested "$@"; then
        run_the_long_e2e_suite
    else
        run_the_short_e2e_suite
    fi
    summarise_and_exit
}

main "$@"
