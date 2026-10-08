# Design: Presidential Debate call-centre simulation

This document records every decision in `src/presidential_debate.c` that a
reviewer could question, and why it was made. The spec is `docs/spec.md`; the
coding contract is `docs/conventions.md`; the sources behind the choices are in
`docs/research.md`.

## 1. The problem in one paragraph

200 callers (one thread each) try to reach a call centre with 5 phone lines and
2 operators. A caller first needs a free line (shared counter `connected`,
guarded by a binary semaphore), then a free operator (counting semaphore with
value 2), spends one second proposing a question, releases the operator, hangs
up (releases the line). The debate lasts `argv[1]` seconds; a timer thread
sleeps that long, `main` joins it, then ends every call thread, destroys the
semaphores and exits 0.

## 2. Globals (spec-mandated, all `static`)

| Name | Type | Role |
| --- | --- | --- |
| `connected_lock` | `sem_t`, initial 1 | binary semaphore; the only guard of `connected` |
| `operators` | `sem_t`, initial `NUM_OPERATORS` | counting semaphore; one unit per free operator |
| `id_lock` | `sem_t`, initial 1 | binary semaphore; the only guard of `next_id` |
| `NUM_OPERATORS` | `int`, 2 | number of operators (spec names it) |
| `NUM_LINES` | `int`, 5 | number of phone lines (spec names it) |
| `connected` | `int`, 0 | callers currently holding a line |
| `next_id` | `int`, 0 | last caller id handed out; each call thread increments it |

Every one is `static` so it has internal linkage: nothing outside this
translation unit can see or touch it, which is what "the static modifier is
used properly for any global variables" asks for. There are no other globals.

The caller id inside `phonecall` is an ordinary automatic (`int id`) local. It
must not be `static`: a function-scope `static` is one object shared by all
200 threads, which would destroy the per-caller identity the id exists to
provide. That is the "thread local variables" half of the rubric line.

### Why `next_id` needs `id_lock`

`id = ++next_id` is a read, an add and a write. Two threads interleaving those
three steps can both read 7, both write 8 and both believe they are caller 8:
two callers with the same id, one id never used. In C99 there is no atomic
increment and no memory model guarantee for unsynchronised shared access, so
the only portable fix is to serialise the read-modify-write. A binary
semaphore (`sem_init(&id_lock, 0, 1)`) is used rather than a `pthread_mutex_t`
so the program uses exactly one synchronisation primitive family, the one the
spec teaches. The answer to the spec's "Do you need synchronization here?" is
therefore yes, and the increment happens literally inside `phonecall` so the
rubric line "next_id ... properly updated in the thread function" is visibly
true without reading a helper.

Ids run 1..200 (`next_id` starts at 0 and the thread takes the incremented
value).

## 3. Thread function: `phonecall`

```
claim id            sem_wait(id_lock); id = ++next_id; sem_post(id_lock)
announce ATTEMPTING
acquire_line        loop: try_claim_line() or sleep(BUSY_RETRY_SECONDS)
announce CONNECTED
propose_question    sem_wait(operators); announce SPEAKING; sleep(QUESTION_SECONDS);
                    announce PROPOSED; sem_post(operators)
announce HUNG_UP
release_line        sem_wait(connected_lock); connected--; sem_post(connected_lock)
return NULL
```

`try_claim_line` is the one place the busy test lives: lock, compare
`connected` with `NUM_LINES`, increment if there is room, unlock, report. It is
a separate function so the critical section is five lines long and can be
unit-tested without threads. `release_line` is its mirror.

### What is inside the critical sections, and what is not

Only the touches of `connected` and `next_id` sit between `sem_wait` and
`sem_post` on a binary semaphore. No `printf`, no `sleep`, no wait on another
semaphore. Two reasons:

1. The rubric awards points for "binary semaphores are used properly not to
   protect non-critical regions of code". Printing is not shared state.
2. Cancellation safety. `pthread_cancel` is acted on only at cancellation
   points, and `sem_wait` and `sleep` are cancellation points. A thread
   cancelled inside a critical section would die holding the lock and every
   other thread would block forever on it. `sem_post` is not a cancellation
   point and neither is an integer compare or increment, so a critical section
   made only of those can never be the place a thread is cancelled.

### Order of "hung up" and `connected--` (deliberate deviation)

The spec's sketch lists "update connected" before "print that the call is
over". This program prints "has hung up!" first and decrements second.

The reason is that the output trace must be a sound witness of the line
invariant. The e2e tests reconstruct the number of lines in use as
`(connects lines seen) - (hung up lines seen)` and assert it never exceeds 5.
With print-after-decrement, thread X can decrement, be preempted before it
prints, thread Y can then claim the freed line and print "connects", and the
trace shows a sixth connection before X's "hung up" appears: a false alarm
from a correct program. With print-before-decrement every "hung up" line
precedes its decrement and every "connects" line follows its increment, so
`connects - hungups <= increments - decrements = connected <= NUM_LINES` holds
at every prefix of the trace.

The spec already uses this print-then-release order for operators ("Print a
message that the question proposal is complete (and update the semaphore)"),
so the lines step just follows the same pattern. The shared state is still
updated in a critical section exactly as required; only the position of one
`printf` moved. README.txt points this out so a grader is not surprised.

### `QUESTION_SECONDS` = 1 versus the spec's "sleep(3)"

The spec says "Simulate a question proposal by sleeping for 1 second
(sleep(3))". The "(3)" is a manual-page section reference (`sleep(3)` is the
C library function, as opposed to `sleep(1)` the shell command), not an
argument of three seconds; the sentence itself says one second. The program
therefore sleeps `QUESTION_SECONDS`, an `enum` constant equal to 1, and the
retry delay for a busy line is `BUSY_RETRY_SECONDS`, also 1, as the spec says
("try again in 1 second"). Both are named so the choice is visible and
changeable in one place; README.txt notes the reading of "(3)".

### The busy case prints nothing

The spec's five output templates have no "busy" line and the sketch only says
"exit the critical section and try again in 1 second", so the busy branch is
silent. Printing a busy line every second for up to 195 waiting threads would
also drown the trace.

## 4. Timer thread and termination order

`main` creates the timer thread (`debate_timer`, which just `sleep`s for the
debate length) and `pthread_join`s it. That is the spec's required mechanism
for blocking `main` for the duration of the debate.

When the join returns the sequence is, in this exact order:

1. `pthread_cancel` every call thread.
2. `pthread_join` every call thread.
3. `sem_destroy` every semaphore.
4. `return EXIT_SUCCESS` from `main` (which runs `exit`, flushing stdio).

Why cancel: most of the 200 threads are blocked in `sem_wait(&operators)` or
sleeping in the busy loop, and they would never finish on their own inside the
debate length; the spec says "your main thread needs to terminate all
threads". Deferred cancellation delivers at the next cancellation point, which
for these threads is the `sem_wait` or `sleep` they are already in.

Why join after cancel: `pthread_join` on a cancelled thread returns once the
thread is really gone (with `PTHREAD_CANCELED` as its result). After the join
loop no thread exists that could still be waiting on, or about to post, a
semaphore, so `sem_destroy` is legal (destroying a semaphore with waiters is
undefined behaviour). This is the only order that satisfies both rubric lines
"threads are created ... and joined properly" and "all semaphores are correctly
initialized and destroyed" at the same time. Joining also reclaims each
thread's resources before exit, which is why the threads are not detached: a
detached thread cannot be joined and there would be no safe moment to destroy
the semaphores.

Why not `pthread_exit` from main or `exit` straight away: both would leave 200
threads mid-flight, with semaphores still in use, and would make "destroyed"
a lie.

A thread cancelled while it holds an operator unit or a line leaves
`operators` and `connected` at their last values. That is harmless: nothing
reads them after the join loop and `sem_destroy` does not care about the count.

### Cancellation is disabled around every `printf`

`announce` (the one function that prints a trace line) wraps its `printf` in
`pthread_setcancelstate(PTHREAD_CANCEL_DISABLE)` / restore. POSIX lists
`printf` among the functions that *may* be cancellation points, and glibc's
stdio takes a per-stream lock for the duration of the call. A thread cancelled
inside `printf` would die holding the `stdout` lock, and `exit`'s final flush
(or any other thread's `printf`) would then deadlock. Disabling cancellation
for the few microseconds of a print removes the possibility instead of
relying on one C library's behaviour. The cancel request is not lost: it is
acted on at the thread's next cancellation point after the state is restored.

## 5. Output

`stdout` is switched to line buffering with `setvbuf(stdout, NULL, _IOLBF, 0)`
before any output. When stdout is a terminal it is line-buffered already, but
when it is a pipe or file (every test, and any `./presidential_debate 10 >
out.txt` a grader runs) it is fully buffered by default: up to 4 KiB of trace
would sit in memory and be written only at exit, so the trace would arrive
out of time order with respect to what the user sees, and any abnormal end
would lose it. With line buffering each `printf` of a complete line becomes
one `write`, lines never interleave mid-line (stdio holds the stream lock for
the whole call), and the order in the file is the order the events were
printed.

The five lines, with the id substituted, are the spec's templates read as five
lines (the spec prints them run together on one line with `...` separating
them; the trailing ` ...` on three of them is kept because it is part of the
text, not the separator):

```
Thread 7 is attempting to connect ...
Thread 7 connects to an available line, call ringing ...
Thread 7 is speaking to an operator.
Thread 7 has proposed a question for candidates! The operator has left ...
Thread 7 has hung up!
```

`[CALLER_ID]` in the spec is a placeholder for the value of `id` ("Note that
[CALLER_ID] is the value of the id variable"), so the brackets are not printed.

The templates live in one table (`CALL_MESSAGES`, indexed by the `CallStage`
enum) and `format_call_message` renders one into a caller-supplied buffer so
the unit tests can compare exact strings without a thread or a pipe.

## 6. Argument handling

`parse_debate_seconds(const char *text, unsigned int *seconds)` accepts only a
string that starts with a digit, converts cleanly with `strtol` (no trailing
characters, no `ERANGE`), is at least 1 and at most `INT_MAX`. Leading
whitespace and a `+` sign are rejected deliberately: `strtol` would accept
them, but " 3" and "+3" are not what a user means by a debate length and
accepting them hides typos. Anything else prints `Usage: presidential_debate
<debate seconds>` on stderr and exits `EXIT_FAILURE`. `unsigned int` is the
parameter type of `sleep`, so the value is stored in that type once.

## 7. Error handling

Every `sem_init`, `sem_wait`, `sem_post`, `pthread_create`, `pthread_cancel`,
`pthread_join` and `pthread_setcancelstate` return value is checked.
`pthread_*` functions return an error number (they do not set `errno`);
`sem_*` return -1 and set `errno`. Two tiny helpers keep that distinction in
one place: `fail_on_errno(int failed, const char *what)` for the `sem_*`
family and `fail_on_error(int error, const char *what)` for the pthread
family. Both print `what: strerror` to stderr and `exit(EXIT_FAILURE)`.

`sem_wait` can return `EINTR` if a signal lands; `wait_on` retries in that
case so a stray signal cannot make a thread skip its lock.

A failure inside a call thread (which cannot happen with validly initialised
semaphores) calls `exit` from that thread. That abandons the other threads,
but it is a fatal, never-expected path and the alternative (propagating a
status back through 200 joins) would add machinery for a case the program
cannot reach.

## 8. Function map

| Function | One line |
| --- | --- |
| `print_usage` | usage line to stderr |
| `parse_debate_seconds` | validate `argv[1]` into an `unsigned int` |
| `fail_on_errno`, `fail_on_error` | report and exit on a failed system / pthread call |
| `wait_on`, `signal_on` | `sem_wait` with EINTR retry, `sem_post`, both checked |
| `format_call_message` | render a `CallStage` template with the id into a buffer |
| `announce` | print one trace line with cancellation disabled |
| `try_claim_line` | critical section: take a line if `connected < NUM_LINES` |
| `acquire_line` | retry `try_claim_line` every `BUSY_RETRY_SECONDS` |
| `release_line` | critical section: `connected--` |
| `propose_question` | wait for an operator, speak, sleep, post |
| `phonecall` | the thread function (spec name) |
| `debate_timer` | the timer thread function: sleep for the debate length |
| `initialize_semaphores`, `destroy_semaphores` | all three `sem_init` / `sem_destroy` |
| `start_calls`, `end_calls` | create 200 threads; cancel then join 200 threads |
| `run_debate` | create and join the timer thread |
| `main` | line-buffer stdout, parse, init, start, run, end, destroy |

`NUM_CALLS` (200), `QUESTION_SECONDS` (1) and `BUSY_RETRY_SECONDS` (1) are
`enum` constants; `NUM_OPERATORS` and `NUM_LINES` stay `static int` because the
spec declares them that way.

## 9. Testing strategy

Unit tests (`test/unit/test_presidential_debate.c`) include the source with
`main` renamed to `program_main`, so every `static` function is callable:
argument parsing (accept 1, 3, 10, 100, `INT_MAX`; reject empty, `0`,
negative, text, trailing garbage, leading space, `+`, overflow), the five
message templates for ids 1, 7 and 200, truncation on a tiny buffer,
`try_claim_line` / `release_line` on a freshly initialised semaphore set with
`connected` driven to the boundary, and `debate_timer` with a zero-second
argument.

End-to-end tests (`test/e2e/`) run the release binary with stdout piped to a
file under `timeout`, then check the trace with `awk`: every line matches one
of the five templates, the "attempting" ids are exactly 1..200 with no
duplicates, each id's lines appear in template order with no stage skipped,
`connects - hung up` never exceeds 5 and `speaking - proposed` never exceeds 2
at any prefix, at least one call completed, exit status 0, wall time at most
the debate length plus 2 seconds. Bad arguments (none, `0`, `-3`, `abc`, `3x`)
exit non-zero with a usage line. `make test` runs 3 s and 10 s; `make
test-long` runs 20, 50 and 100 s.
