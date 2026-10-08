# Presidential Debate (pthreads + semaphores) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single C file, `src/presidential_debate.c`, that simulates 200 callers competing for 5 lines and 2 operators for `argv[1]` seconds, proven by unit tests and trace-checking end-to-end tests.

**Architecture:** One translation unit with spec-mandated `static` globals (two binary semaphores, one counting semaphore, the counters), small named functions for every critical section and every step of a call, a `phonecall` thread function, a `debate_timer` thread function, and a `main` that line-buffers stdout, validates the argument, creates 200 threads, joins the timer, cancels and joins every call thread, destroys the semaphores and exits 0. Unit tests include the source with `main` renamed; e2e tests parse the trace with awk.

**Tech Stack:** C99, POSIX threads and semaphores (`-pthread -D_POSIX_C_SOURCE=200809L`), GNU make 4.4, bash, awk, `gcc -fanalyzer`.

**Spec:** `docs/spec.md` (course spec), `docs/design.md` (decisions and rationale), `docs/conventions.md` (contract).

## Global Constraints

- Deliverable source is exactly `src/presidential_debate.c`; `make dist` ships it with `README.txt` and a flat `Makefile`.
- Compile and link with `-std=c99 -D_POSIX_C_SOURCE=200809L -pthread`; warnings `-Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wconversion -Wvla -Werror`; `make check` runs `gcc -fanalyzer` clean.
- Globals exactly: `static sem_t connected_lock; static sem_t operators; static int NUM_OPERATORS = 2; static int NUM_LINES = 5; static int connected = 0;` plus `static int next_id` and `static sem_t id_lock`. Nothing else at file scope but constants.
- 200 call threads (`NUM_CALLS`), debate length from `argv[1]` validated as a positive integer.
- Output lines are exactly: `Thread <id> is attempting to connect ...`, `Thread <id> connects to an available line, call ringing ...`, `Thread <id> is speaking to an operator.`, `Thread <id> has proposed a question for candidates! The operator has left ...`, `Thread <id> has hung up!`
- Binary semaphores guard only the `connected` / `next_id` touches. No printing or sleeping inside a critical section.
- Termination order: cancel every call thread, join every call thread, destroy every semaphore, exit 0.
- `stdout` line-buffered via `setvbuf` before any output.
- Every function has a header comment; non-obvious globals have a one-line comment; no narration inside bodies; the `=== start` markers never get committed.
- Conventional-commit subjects; never push; no AI attribution anywhere.
- `make test` runs unit tests plus the 3 s and 10 s debates; `make test-long` runs 20, 50 and 100 s.

## Review Focus

1. Output piped to a file must contain every line that was printed before termination, in print order: Task 5 sets `_IOLBF`; Task 6 reads the trace only through a pipe/file.
2. A thread cancelled inside a `printf` must not leave `stdout` locked (deadlock at exit): Task 3's `announce` disables cancellation around the print; Task 6's wall-time assertion would catch a hang.
3. A `pthread_cancel` on a call thread that already finished (short debates leave most unfinished, long ones finish all 200): Task 6 runs 3 s (some finished) and `make test-long` 100 s (all finished) and asserts exit 0.
4. `argv[1]` such as `3x`, ` 3`, `+3`, `0`, `-1`, overflow: Task 2 unit tests and Task 6 `bad_args.sh`.
5. The trace-reconstructed line count must never exceed 5 even under preemption: Task 5 prints "hung up" before `connected--` (design.md section 3) and Task 6 asserts the bound on every prefix.

---

### Task 1: Scaffold (Makefile, harness, runner, README skeleton)

**Files:**
- Create: `.gitignore`, `Makefile`, `test/unit/check.h`, `test/run_tests.sh`, `README.txt`
- Already present: `docs/conventions.md`, `docs/spec.md`, `docs/design.md`, `docs/plan.md`, `docs/research.md`

**Interfaces:**
- Produces: `make all|debug|test|test-long|check|run|dist|clean`; `build/presidential_debate`; `test/run_tests.sh [long]`; `TEST_CFLAGS` and `CC` env vars honoured by the runner; `check.h` macros `CHECK`, `CHECK_EQ_INT`, `CHECK_EQ_STR`, `CHECK_REPORT`.

- [ ] **Step 1: `.gitignore`**

```
build/
dist/
output.txt
core
core.*
*.o
*.d
*~
.*.swp
```

- [ ] **Step 2: `Makefile`**

```make
# Makefile for CS230 project 4, presidential_debate.
# Targets follow docs/conventions.md section 3: all, debug, test, test-long,
# check, run, dist, clean.

CC ?= gcc

# -std=c99 is the course floor. _POSIX_C_SOURCE=200809L exposes pthreads,
# semaphores, sleep and strtol's errno contract under strict C99. -pthread
# belongs on both compile and link lines so glibc sets up threading.
BASE_FLAGS := -std=c99 -D_POSIX_C_SOURCE=200809L -pthread

# Mandatory warning set, all fatal (docs/conventions.md section 2).
WARN_FLAGS := -Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes \
              -Wmissing-prototypes -Wconversion -Wvla -Werror

RELEASE_FLAGS := -O2
DEBUG_FLAGS := -O0 -g3

# -MMD -MP writes a .d file per object so header edits rebuild dependents.
CFLAGS ?= $(BASE_FLAGS) $(WARN_FLAGS) $(RELEASE_FLAGS) -MMD -MP
LDFLAGS ?= -pthread

# The unit test includes the source file directly, so functions the test does
# not call look unused to the compiler; that warning alone is waived there.
TEST_CFLAGS := $(BASE_FLAGS) $(WARN_FLAGS) $(DEBUG_FLAGS) -Wno-unused-function

SRC_DIR := src
BUILD_DIR := build
DIST_DIR := dist
NAME := presidential_debate

SOURCES := $(wildcard $(SRC_DIR)/*.c)
OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)
DEBUG_OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/debug/%.o)
CHECK_OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/check/%.o)
DEPENDS := $(OBJECTS:.o=.d) $(DEBUG_OBJECTS:.o=.d)

PROGRAM := $(BUILD_DIR)/$(NAME)
DEBUG_PROGRAM := $(BUILD_DIR)/debug/$(NAME)

.PHONY: all debug test test-long check run dist clean

# all: release binary in build/.
all: $(PROGRAM)

# debug: -O0 -g3 binary in build/debug/ so it never collides with release objects.
debug: $(DEBUG_PROGRAM)

$(PROGRAM): $(OBJECTS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(DEBUG_PROGRAM): $(DEBUG_OBJECTS)
	$(CC) $(BASE_FLAGS) $(WARN_FLAGS) $(DEBUG_FLAGS) -o $@ $^ $(LDFLAGS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/debug/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(BASE_FLAGS) $(WARN_FLAGS) $(DEBUG_FLAGS) -MMD -MP -c -o $@ $<

# check: gcc's static analyzer over every source; objects go to build/check/.
$(BUILD_DIR)/check/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(BASE_FLAGS) $(WARN_FLAGS) -fanalyzer -c -o $@ $<

check: $(CHECK_OBJECTS)

# test: unit tests plus the 3 s and 10 s debates. test-long adds 20, 50, 100 s.
test: $(PROGRAM)
	CC="$(CC)" TEST_CFLAGS="$(TEST_CFLAGS)" PROGRAM="$(PROGRAM)" test/run_tests.sh

test-long: $(PROGRAM)
	CC="$(CC)" TEST_CFLAGS="$(TEST_CFLAGS)" PROGRAM="$(PROGRAM)" test/run_tests.sh long

# run: a 3 second debate, the spec's first test case.
run: $(PROGRAM)
	$(PROGRAM) 3

# dist: the flat Gradescope bundle, then prove it builds with the course flags.
define DIST_MAKEFILE
# Flat Makefile for the Gradescope submission: builds presidential_debate here.
CC ?= gcc
CFLAGS ?= -std=c99 -D_POSIX_C_SOURCE=200809L -pthread -Wall -Wextra -O2
LDFLAGS ?= -pthread

all: presidential_debate

presidential_debate: presidential_debate.c
	$$(CC) $$(CFLAGS) -o $$@ $$< $$(LDFLAGS)

clean:
	rm -f presidential_debate

.PHONY: all clean
endef

dist: $(SOURCES) README.txt
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)
	cp $(SOURCES) README.txt $(DIST_DIR)/
	$(file >$(DIST_DIR)/Makefile,$(DIST_MAKEFILE))
	$(MAKE) -C $(DIST_DIR)

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR) output.txt

-include $(DEPENDS)
```

- [ ] **Step 3: `test/unit/check.h`** is the harness verbatim from `docs/conventions.md` section 6.

- [ ] **Step 4: `test/run_tests.sh`**

```bash
#!/usr/bin/env bash
# Builds and runs every unit test, then the e2e scripts.
# Usage: test/run_tests.sh [long]   ("long" runs the 20/50/100 s debates instead of 3/10 s)
set -euo pipefail
cd "$(dirname "$0")/.."

CC="${CC:-gcc}"
TEST_CFLAGS="${TEST_CFLAGS:--std=c99 -D_POSIX_C_SOURCE=200809L -pthread -Wall -Wextra -O0 -g3 -Wno-unused-function}"
export PROGRAM="${PROGRAM:-build/presidential_debate}"
mode="${1:-short}"
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

run_unit_tests() {
    mkdir -p build/test
    local source binary
    for source in test/unit/test_*.c; do
        binary="build/test/$(basename "${source%.c}")"
        # shellcheck disable=SC2086
        "$CC" $TEST_CFLAGS -o "$binary" "$source" -pthread
        "$binary" >/dev/null
        report $? "$binary"
    done
}

run_e2e() {
    local script=$1; shift
    set +e
    "$script" "$@" >/dev/null
    local status=$?
    set -e
    report "$status" "$script $*"
}

run_unit_tests
if [ "$mode" = "long" ]; then
    for seconds in 20 50 100; do run_e2e test/e2e/debate.sh "$seconds"; done
else
    run_e2e test/e2e/bad_args.sh
    for seconds in 3 10; do run_e2e test/e2e/debate.sh "$seconds"; done
fi

echo "$failures failure(s)"
exit $((failures > 0))
```

Note `"$binary" >/dev/null; report $? ...` under `set -e` must be written as `if "$binary" >/dev/null; then report 0 ...; else report 1 ...; fi` (the real file does this).

- [ ] **Step 5: `README.txt` skeleton** with the section headers from `docs/conventions.md` section 8 and the line `Video: <VIDEO URL TO BE ADDED>`.

- [ ] **Step 6: Commit**

```bash
git add .gitignore Makefile test/unit/check.h test/run_tests.sh README.txt docs/
git commit -m "build: scaffold Makefile, test harness and docs"
```

---

### Task 2: Argument parsing and usage

**Files:**
- Create: `src/presidential_debate.c`
- Create: `test/unit/test_presidential_debate.c`

**Interfaces:**
- Produces: `static int parse_debate_seconds(const char *text, unsigned int *seconds)` returns 1 and stores the value when `text` is a decimal integer in 1..INT_MAX with no sign, no leading whitespace and no trailing characters; else returns 0. `static void print_usage(const char *program)` prints `Usage: <program> <debate seconds>` on stderr. `int main(int argc, char *argv[])` exits `EXIT_FAILURE` after usage when `argc != 2` or parsing fails.

- [ ] **Step 1: Failing test**

```c
#define main program_main
int program_main(int argc, char *argv[]);
#include "../../src/presidential_debate.c"
#undef main
#include "check.h"

static void test_parse_debate_seconds_accepts_positive_integers(void) {
    unsigned int seconds = 0;
    CHECK(parse_debate_seconds("1", &seconds));
    CHECK_EQ_INT(seconds, 1);
    CHECK(parse_debate_seconds("3", &seconds));
    CHECK_EQ_INT(seconds, 3);
    CHECK(parse_debate_seconds("100", &seconds));
    CHECK_EQ_INT(seconds, 100);
    CHECK(parse_debate_seconds("2147483647", &seconds));
    CHECK_EQ_INT(seconds, 2147483647);
}

static void test_parse_debate_seconds_rejects_bad_input(void) {
    unsigned int seconds = 42;
    CHECK(!parse_debate_seconds("", &seconds));
    CHECK(!parse_debate_seconds("0", &seconds));
    CHECK(!parse_debate_seconds("-3", &seconds));
    CHECK(!parse_debate_seconds("abc", &seconds));
    CHECK(!parse_debate_seconds("3x", &seconds));
    CHECK(!parse_debate_seconds(" 3", &seconds));
    CHECK(!parse_debate_seconds("+3", &seconds));
    CHECK(!parse_debate_seconds("2147483648", &seconds));
    CHECK(!parse_debate_seconds("99999999999999999999", &seconds));
    CHECK(!parse_debate_seconds(NULL, &seconds));
    CHECK_EQ_INT(seconds, 42);
}

int main(void) {
    test_parse_debate_seconds_accepts_positive_integers();
    test_parse_debate_seconds_rejects_bad_input();
    CHECK_REPORT("test_presidential_debate");
}
```

- [ ] **Step 2: Run, expect failure** (compile error: `parse_debate_seconds` undeclared).

Run: `make test`

- [ ] **Step 3: Minimal implementation** in `src/presidential_debate.c`

```c
/*
 * presidential_debate.c: 200 callers compete for 5 phone lines and 2 operators
 * for the length of a debate given in seconds on the command line.
 * Design rationale: docs/design.md.
 */
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

/* Print the usage line on stderr. */
static void print_usage(const char *program) {
    fprintf(stderr, "Usage: %s <debate seconds>\n", program);
}

/*
 * Validate text as a debate length: unsigned decimal digits only, 1..INT_MAX.
 * @return 1 and store the value in *seconds on success, 0 otherwise.
 */
static int parse_debate_seconds(const char *text, unsigned int *seconds) {
    char *end;
    long value;
    if (text == NULL || *text < '0' || *text > '9') {
        return 0;
    }
    errno = 0;
    value = strtol(text, &end, 10);
    if (errno != 0 || *end != '\0' || value < 1 || value > INT_MAX) {
        return 0;
    }
    *seconds = (unsigned int)value;
    return 1;
}

int main(int argc, char *argv[]) {
    unsigned int seconds;
    if (argc != 2 || !parse_debate_seconds(argv[1], &seconds)) {
        print_usage(argc > 0 ? argv[0] : "presidential_debate");
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
```

- [ ] **Step 4: Run, expect pass**: `make test` (e2e scripts do not exist yet; the runner must tolerate their absence until Task 6, so for this task run the unit binary directly: `make && test/run_tests.sh` reports the unit test PASS and the missing e2e scripts FAIL, which is expected until Task 6).

- [ ] **Step 5: Commit**

```bash
git add src/presidential_debate.c test/unit/test_presidential_debate.c
git commit -m "feat: validate the debate length argument"
```

---

### Task 3: Message templates and `announce`

**Files:**
- Modify: `src/presidential_debate.c`
- Modify: `test/unit/test_presidential_debate.c`

**Interfaces:**
- Produces: `typedef enum { STAGE_ATTEMPTING, STAGE_CONNECTED, STAGE_SPEAKING, STAGE_PROPOSED, STAGE_HUNG_UP, STAGE_COUNT } CallStage;` `static int format_call_message(char *buffer, size_t capacity, int id, CallStage stage)` returns the length written or -1 if it did not fit; `static void announce(int id, CallStage stage)` prints the line plus newline with cancellation disabled; helpers `static void die(const char *what, int error)`, `static void check_errno(int failed, const char *what)`, `static void check_error(int error, const char *what)`.

- [ ] **Step 1: Failing tests**

```c
static void test_format_call_message_matches_spec_templates(void) {
    char line[MESSAGE_CAPACITY];
    CHECK(format_call_message(line, sizeof line, 7, STAGE_ATTEMPTING) > 0);
    CHECK_EQ_STR(line, "Thread 7 is attempting to connect ...");
    CHECK(format_call_message(line, sizeof line, 7, STAGE_CONNECTED) > 0);
    CHECK_EQ_STR(line, "Thread 7 connects to an available line, call ringing ...");
    CHECK(format_call_message(line, sizeof line, 7, STAGE_SPEAKING) > 0);
    CHECK_EQ_STR(line, "Thread 7 is speaking to an operator.");
    CHECK(format_call_message(line, sizeof line, 7, STAGE_PROPOSED) > 0);
    CHECK_EQ_STR(line, "Thread 7 has proposed a question for candidates! The operator has left ...");
    CHECK(format_call_message(line, sizeof line, 7, STAGE_HUNG_UP) > 0);
    CHECK_EQ_STR(line, "Thread 7 has hung up!");
}

static void test_format_call_message_uses_the_given_id(void) {
    char line[MESSAGE_CAPACITY];
    CHECK(format_call_message(line, sizeof line, 1, STAGE_HUNG_UP) > 0);
    CHECK_EQ_STR(line, "Thread 1 has hung up!");
    CHECK(format_call_message(line, sizeof line, 200, STAGE_HUNG_UP) > 0);
    CHECK_EQ_STR(line, "Thread 200 has hung up!");
}

static void test_format_call_message_reports_truncation(void) {
    char tiny[8];
    CHECK_EQ_INT(format_call_message(tiny, sizeof tiny, 7, STAGE_ATTEMPTING), -1);
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implementation**

```c
#include <pthread.h>
#include <string.h>

enum {
    MESSAGE_CAPACITY = 128   /* longest template plus a caller id, with room */
};

/* The five trace lines of a call, in the order a call prints them. */
typedef enum {
    STAGE_ATTEMPTING,
    STAGE_CONNECTED,
    STAGE_SPEAKING,
    STAGE_PROPOSED,
    STAGE_HUNG_UP,
    STAGE_COUNT
} CallStage;

/* Text after "Thread <id> " for each CallStage; the spec's templates. */
static const char *const STAGE_MESSAGES[STAGE_COUNT] = {
    "is attempting to connect ...",
    "connects to an available line, call ringing ...",
    "is speaking to an operator.",
    "has proposed a question for candidates! The operator has left ...",
    "has hung up!"
};

/* Report a failed call and end the process; error is an errno value. */
static void die(const char *what, int error) {
    fprintf(stderr, "presidential_debate: %s: %s\n", what, strerror(error));
    exit(EXIT_FAILURE);
}

/* die() with errno when failed is non-zero (for calls that return -1 and set errno). */
static void check_errno(int failed, const char *what) {
    if (failed) {
        die(what, errno);
    }
}

/* die() when error is non-zero (for pthread calls, which return the error number). */
static void check_error(int error, const char *what) {
    if (error != 0) {
        die(what, error);
    }
}

/*
 * Render the trace line for one stage of a call into buffer.
 * @return the length written, or -1 if capacity was too small.
 */
static int format_call_message(char *buffer, size_t capacity, int id, CallStage stage) {
    int length = snprintf(buffer, capacity, "Thread %d %s", id, STAGE_MESSAGES[stage]);
    if (length < 0 || (size_t)length >= capacity) {
        return -1;
    }
    return length;
}

/* Print one trace line; cancellation is off during the print (docs/design.md section 4). */
static void announce(int id, CallStage stage) {
    char message[MESSAGE_CAPACITY];
    int previous_state;
    int restored_state;
    if (format_call_message(message, sizeof message, id, stage) < 0) {
        die("format_call_message", EOVERFLOW);
    }
    check_error(pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_state), "pthread_setcancelstate");
    check_errno(puts(message) == EOF, "puts");
    check_error(pthread_setcancelstate(previous_state, &restored_state), "pthread_setcancelstate");
}
```

- [ ] **Step 4: Run, expect pass** (`make && test/run_tests.sh` unit line PASS).

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: format the five trace lines with the caller id"
```

---

### Task 4: Semaphores, globals and the critical sections

**Files:**
- Modify: `src/presidential_debate.c`
- Modify: `test/unit/test_presidential_debate.c`

**Interfaces:**
- Produces: the spec globals; `static void initialize_semaphores(void)`, `static void destroy_semaphores(void)`, `static void wait_on(sem_t *semaphore)` (EINTR-safe), `static void signal_on(sem_t *semaphore)`, `static int try_claim_line(void)` (1 if a line was taken), `static void release_line(void)`.

- [ ] **Step 1: Failing tests**

```c
static void test_try_claim_line_respects_num_lines(void) {
    initialize_semaphores();
    connected = 0;
    CHECK(try_claim_line());
    CHECK_EQ_INT(connected, 1);
    connected = NUM_LINES - 1;
    CHECK(try_claim_line());
    CHECK_EQ_INT(connected, NUM_LINES);
    CHECK(!try_claim_line());
    CHECK_EQ_INT(connected, NUM_LINES);
    release_line();
    CHECK_EQ_INT(connected, NUM_LINES - 1);
    connected = 0;
    destroy_semaphores();
}

static void test_semaphores_start_with_spec_values(void) {
    int value = -1;
    initialize_semaphores();
    CHECK_EQ_INT(sem_getvalue(&connected_lock, &value), 0);
    CHECK_EQ_INT(value, 1);
    CHECK_EQ_INT(sem_getvalue(&operators, &value), 0);
    CHECK_EQ_INT(value, NUM_OPERATORS);
    CHECK_EQ_INT(sem_getvalue(&id_lock, &value), 0);
    CHECK_EQ_INT(value, 1);
    destroy_semaphores();
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implementation**

```c
#include <semaphore.h>

static sem_t connected_lock;      /* binary semaphore: the only guard of connected */
static sem_t operators;           /* counting semaphore: one unit per free operator */
static sem_t id_lock;             /* binary semaphore: the only guard of next_id */
static int NUM_OPERATORS = 2;
static int NUM_LINES = 5;
static int connected = 0;         /* callers currently holding a phone line */
static int next_id = 0;           /* last caller id handed out; ids run 1..NUM_CALLS */

/* sem_init all three semaphores with their starting values. */
static void initialize_semaphores(void) {
    check_errno(sem_init(&connected_lock, 0, 1) == -1, "sem_init connected_lock");
    check_errno(sem_init(&operators, 0, (unsigned int)NUM_OPERATORS) == -1, "sem_init operators");
    check_errno(sem_init(&id_lock, 0, 1) == -1, "sem_init id_lock");
}

/* sem_destroy all three semaphores; only legal once no thread can touch them. */
static void destroy_semaphores(void) {
    check_errno(sem_destroy(&id_lock) == -1, "sem_destroy id_lock");
    check_errno(sem_destroy(&operators) == -1, "sem_destroy operators");
    check_errno(sem_destroy(&connected_lock) == -1, "sem_destroy connected_lock");
}

/* sem_wait that retries when a signal interrupts it. */
static void wait_on(sem_t *semaphore) {
    int result;
    do {
        result = sem_wait(semaphore);
    } while (result == -1 && errno == EINTR);
    check_errno(result == -1, "sem_wait");
}

/* sem_post, checked. */
static void signal_on(sem_t *semaphore) {
    check_errno(sem_post(semaphore) == -1, "sem_post");
}

/*
 * Critical section on connected: take a line if one is free.
 * @return 1 if this caller now holds a line, 0 if every line is busy.
 */
static int try_claim_line(void) {
    int claimed = 0;
    wait_on(&connected_lock);
    if (connected < NUM_LINES) {
        connected++;
        claimed = 1;
    }
    signal_on(&connected_lock);
    return claimed;
}

/* Critical section on connected: give the line back. */
static void release_line(void) {
    wait_on(&connected_lock);
    connected--;
    signal_on(&connected_lock);
}
```

- [ ] **Step 4: Run, expect pass.**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: add the spec semaphores and the connected critical sections"
```

---

### Task 5: Call threads, timer thread and `main`

**Files:**
- Modify: `src/presidential_debate.c`
- Modify: `test/unit/test_presidential_debate.c`

**Interfaces:**
- Produces: `static void sleep_fully(unsigned int seconds)`, `static void acquire_line(void)`, `static void propose_question(int id)`, `static void *phonecall(void *vargp)`, `static void *debate_timer(void *vargp)` (vargp points at an `unsigned int`), `static void start_calls(pthread_t calls[NUM_CALLS])`, `static void end_calls(pthread_t calls[NUM_CALLS])`, `static void run_debate(unsigned int seconds)`; `main` runs the whole simulation.

- [ ] **Step 1: Failing tests**

```c
static void test_phonecall_takes_a_unique_id_and_frees_its_line(void) {
    pthread_t calls[3];
    size_t i;
    initialize_semaphores();
    connected = 0;
    next_id = 0;
    for (i = 0; i < 3; i++) {
        CHECK_EQ_INT(pthread_create(&calls[i], NULL, phonecall, NULL), 0);
    }
    for (i = 0; i < 3; i++) {
        CHECK_EQ_INT(pthread_join(calls[i], NULL), 0);
    }
    CHECK_EQ_INT(next_id, 3);
    CHECK_EQ_INT(connected, 0);
    destroy_semaphores();
}

static void test_debate_timer_returns_after_the_given_seconds(void) {
    unsigned int zero = 0;
    CHECK(debate_timer(&zero) == NULL);
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implementation**

```c
#include <unistd.h>

enum {
    NUM_CALLS = 200,          /* phone-call threads created for the debate */
    QUESTION_SECONDS = 1,     /* the spec's "sleeping for 1 second (sleep(3))" */
    BUSY_RETRY_SECONDS = 1,   /* the spec's "try again in 1 second" */
    MESSAGE_CAPACITY = 128
};

/* sleep for the whole duration even if a signal cuts a sleep short. */
static void sleep_fully(unsigned int seconds) {
    while (seconds > 0) {
        seconds = sleep(seconds);
    }
}

/* Keep trying for a line until one is free. */
static void acquire_line(void) {
    while (!try_claim_line()) {
        sleep_fully(BUSY_RETRY_SECONDS);
    }
}

/* Hold an operator for QUESTION_SECONDS and announce both ends of the exchange. */
static void propose_question(int id) {
    wait_on(&operators);
    announce(id, STAGE_SPEAKING);
    sleep_fully(QUESTION_SECONDS);
    announce(id, STAGE_PROPOSED);
    signal_on(&operators);
}

/* Thread function for one phone call: takes the next id, then runs the spec's steps. */
static void *phonecall(void *vargp) {
    int id;
    (void)vargp;
    wait_on(&id_lock);
    id = ++next_id;
    signal_on(&id_lock);
    announce(id, STAGE_ATTEMPTING);
    acquire_line();
    announce(id, STAGE_CONNECTED);
    propose_question(id);
    announce(id, STAGE_HUNG_UP);
    release_line();
    return NULL;
}

/* Thread function for the debate clock. @param vargp points at the length in seconds. */
static void *debate_timer(void *vargp) {
    const unsigned int *seconds = vargp;
    sleep_fully(*seconds);
    return NULL;
}

/* Create every phone-call thread. */
static void start_calls(pthread_t calls[NUM_CALLS]) {
    size_t i;
    for (i = 0; i < NUM_CALLS; i++) {
        check_error(pthread_create(&calls[i], NULL, phonecall, NULL), "pthread_create phonecall");
    }
}

/* Cancel every phone-call thread, then join each so none survives this call. */
static void end_calls(pthread_t calls[NUM_CALLS]) {
    size_t i;
    for (i = 0; i < NUM_CALLS; i++) {
        check_error(pthread_cancel(calls[i]), "pthread_cancel phonecall");
    }
    for (i = 0; i < NUM_CALLS; i++) {
        check_error(pthread_join(calls[i], NULL), "pthread_join phonecall");
    }
}

/* Block until the timer thread has slept for the debate length. */
static void run_debate(unsigned int seconds) {
    pthread_t timer;
    check_error(pthread_create(&timer, NULL, debate_timer, &seconds), "pthread_create timer");
    check_error(pthread_join(timer, NULL), "pthread_join timer");
}

int main(int argc, char *argv[]) {
    pthread_t calls[NUM_CALLS];
    unsigned int seconds;
    if (argc != 2 || !parse_debate_seconds(argv[1], &seconds)) {
        print_usage(argc > 0 ? argv[0] : "presidential_debate");
        return EXIT_FAILURE;
    }
    check_errno(setvbuf(stdout, NULL, _IOLBF, 0) != 0, "setvbuf");
    initialize_semaphores();
    start_calls(calls);
    run_debate(seconds);
    end_calls(calls);
    destroy_semaphores();
    return EXIT_SUCCESS;
}
```

- [ ] **Step 4: Run, expect pass**; also `make run` prints a 3 s trace and exits 0; `./build/presidential_debate 3 | tail -3` shows complete lines.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: run 200 call threads against 5 lines and 2 operators for the debate length"
```

---

### Task 6: End-to-end trace checks

**Files:**
- Create: `test/e2e/check_trace.sh`, `test/e2e/debate.sh`, `test/e2e/bad_args.sh`

**Interfaces:**
- Consumes: `$PROGRAM` (default `build/presidential_debate`).
- Produces: `check_trace.sh <trace file> <expected attempts> <min completed>` exits non-zero with a reason on the first broken invariant; `debate.sh <seconds>` runs the binary with stdout to a file in `$TMPDIR`, asserts exit 0, wall time <= seconds + 2, and calls `check_trace.sh`; `bad_args.sh` asserts non-zero exit and a `Usage:` line on stderr for no argument, `0`, `-3`, `abc`, `3x`, `1 2`.

- [ ] **Step 1: Write `check_trace.sh`**

```bash
#!/usr/bin/env bash
# Verify a debate trace: line format, unique ids 1..NUM_CALLS, per-id stage
# order, lines in use <= 5 and operators in use <= 2 at every prefix, progress.
# Usage: check_trace.sh <trace> <expected attempts> <min completed>
set -euo pipefail
trace=$1
expected_attempts=$2
min_completed=$3

awk -v expected="$expected_attempts" -v min_completed="$min_completed" '
function fail(reason) { printf "trace line %d: %s: %s\n", NR, reason, $0; exit 1 }
function stage_of(rest) {
    if (rest == "is attempting to connect ...") return 1
    if (rest == "connects to an available line, call ringing ...") return 2
    if (rest == "is speaking to an operator.") return 3
    if (rest == "has proposed a question for candidates! The operator has left ...") return 4
    if (rest == "has hung up!") return 5
    return 0
}
{
    if (match($0, /^Thread [0-9]+ /) == 0) fail("not a trace line")
    id = substr($0, 8, RLENGTH - 8) + 0
    stage = stage_of(substr($0, RLENGTH + 1))
    if (stage == 0) fail("unknown message")
    if (id < 1 || id > 200) fail("id out of range")
    if (stage == 1 && seen[id]++) fail("duplicate attempting id")
    if (last[id] + 0 != stage - 1) fail("stage out of order")
    last[id] = stage
    if (stage == 2) lines++
    if (stage == 5) lines--
    if (lines > 5) fail("more than 5 lines in use")
    if (stage == 3) busy++
    if (stage == 4) busy--
    if (busy > 2) fail("more than 2 operators in use")
    count[stage]++
}
END {
    if (count[1] != expected) { printf "expected %d attempting lines, saw %d\n", expected, count[1]; exit 1 }
    if (count[5] < min_completed) { printf "expected at least %d completed calls, saw %d\n", min_completed, count[5]; exit 1 }
    printf "trace ok: %d lines, %d attempts, %d completed\n", NR, count[1], count[5]
}' "$trace"
```

- [ ] **Step 2: Write `debate.sh`**

```bash
#!/usr/bin/env bash
# Run a debate of N seconds with stdout piped to a file, then check the trace.
# Usage: debate.sh <seconds>
set -euo pipefail
cd "$(dirname "$0")/../.."
seconds=$1
program="${PROGRAM:-build/presidential_debate}"
trace="${TMPDIR:-/tmp}/presidential_debate_${seconds}s.$$"
trap 'rm -f "$trace"' EXIT

start=$EPOCHREALTIME
set +e
timeout $((seconds + 10)) "$program" "$seconds" > "$trace"
status=$?
set -e
elapsed=$(awk -v a="$start" -v b="$EPOCHREALTIME" 'BEGIN { print b - a }')

[ "$status" -eq 0 ] || { echo "exit status $status"; exit 1; }
awk -v e="$elapsed" -v limit=$((seconds + 2)) 'BEGIN { exit !(e <= limit) }' \
    || { echo "took ${elapsed}s, limit $((seconds + 2))s"; exit 1; }
test/e2e/check_trace.sh "$trace" 200 "$seconds"
echo "debate ${seconds}s: exit 0 in ${elapsed}s"
```

- [ ] **Step 3: Write `bad_args.sh`**

```bash
#!/usr/bin/env bash
# Every bad argument exits non-zero with a usage line on stderr and nothing on stdout.
set -euo pipefail
cd "$(dirname "$0")/../.."
program="${PROGRAM:-build/presidential_debate}"

expect_usage() {
    local out err status
    set +e
    out=$(timeout 5 "$program" "$@" 2>/dev/null)
    status=$?
    err=$(timeout 5 "$program" "$@" 2>&1 >/dev/null)
    set -e
    [ "$status" -ne 0 ] || { echo "args '$*': exit 0"; exit 1; }
    [ -z "$out" ] || { echo "args '$*': stdout not empty"; exit 1; }
    grep -q '^Usage: ' <<<"$err" || { echo "args '$*': no usage line"; exit 1; }
}

expect_usage
expect_usage 0
expect_usage -3
expect_usage abc
expect_usage 3x
expect_usage 1 2
echo "bad arguments rejected"
```

- [ ] **Step 4: `chmod +x test/e2e/*.sh test/run_tests.sh`; run `make test`** expecting every line PASS; run `make test-long` once (170 s) expecting PASS.

- [ ] **Step 5: Commit**

```bash
git add test/e2e
git commit -m "test: check debate traces end to end"
```

---

### Task 7: README requirements map, dist, gate

**Files:**
- Modify: `README.txt`

- [ ] **Step 1: Fill README.txt**: overview; build/run; requirements map (each bullet of the spec's "Project Requirements" and the design/style/comments sections mapped to a function name); design notes (termination order, id_lock, QUESTION_SECONDS and the "(3)" reading, hung-up-before-decrement, line buffering); `Video: <VIDEO URL TO BE ADDED>`.

- [ ] **Step 2: Gate**: `make clean && make && make check && make test && make dist`, all exit 0.

- [ ] **Step 3: Commit**

```bash
git add README.txt
git commit -m "docs: map every rubric item to the code in README.txt"
```
