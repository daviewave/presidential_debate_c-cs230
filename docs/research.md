# Research notes: threads, semaphores and cancellation in `presidential_debate.c`

Each section records the sources actually consulted, what they established, the
practice this project adopts, and the specific pitfalls the code is written to
avoid. Local facts were checked on the development machine (gcc 16.2.1,
glibc 2.43) and are marked as such; the course VM may differ in version but not
in the POSIX guarantees relied on here.

## 1. POSIX semaphores versus mutexes

### Sources

- https://man7.org/linux/man-pages/man3/sem_init.3.html
- https://man7.org/linux/man-pages/man3/sem_wait.3.html
- https://man7.org/linux/man-pages/man3/sem_post.3.html
- https://man7.org/linux/man-pages/man3/sem_destroy.3.html
- https://man7.org/linux/man-pages/man7/sem_overview.7.html
- https://pubs.opengroup.org/onlinepubs/9699919799/functions/sem_wait.html
- https://pubs.opengroup.org/onlinepubs/9699919799/functions/sem_destroy.html

### What was learned

- `sem_init(sem, pshared, value)`: `pshared == 0` means the semaphore is shared
  between the threads of one process (the only case this program needs);
  nonzero would require shared memory. `value` is the initial count. Returns 0,
  or -1 with `errno` (`EINVAL` if `value > SEM_VALUE_MAX`). Initialising an
  already-initialised semaphore is undefined behaviour.
- `sem_wait` decrements, blocking while the count is zero; `sem_post`
  increments and wakes one blocked waiter. Both return 0 or -1 with `errno`.
  `sem_wait` "may fail" with `EINTR` when a signal handler interrupts it; POSIX
  says that on any unsuccessful return "the state of the semaphore shall be
  unchanged", so an `EINTR` return has not consumed a count. `sem_post` is
  async-signal-safe and can fail with `EOVERFLOW`.
- A binary semaphore is simply a counting semaphore initialised to 1. Unlike a
  mutex it has no owner, so any thread may post it; that is what the spec
  wants, and it also means nothing stops a bug from posting twice, so the
  lock/unlock pairs must be visibly matched in the code.
- `sem_destroy`: "Destroying a semaphore that other processes or threads are
  currently blocked on produces undefined behaviour" (man7); POSIX adds a
  "may fail" `EBUSY`. Only a semaphore initialised by `sem_init` may be
  destroyed, and it should be destroyed before its memory goes away.
- Nothing forbids using a semaphore from a thread that will later be
  cancelled; the question is only what the thread holds at the moment it is
  cancelled (section 2).

### Adopted in this project

- Three unnamed, process-private semaphores: `connected_lock` (value 1),
  `id_lock` (value 1) and `operators` (value `NUM_OPERATORS`), all
  `sem_init(&s, 0, n)` in `main` before any thread exists, all checked.
- `sem_destroy` is called only after every call thread has been joined, so no
  thread can still be blocked on any of them.
- Every `sem_wait`/`sem_post` return value is checked; a failure prints to
  `stderr` and exits, since a broken lock cannot be reasoned about.

### Pitfalls avoided

- Destroying semaphores while threads are still blocked on them (undefined).
- Treating a binary semaphore as a mutex with ownership: every wait has one
  textually paired post in the same function, with no early `return` between.
- Initialising the semaphores twice or after threads are already running.

## 2. `pthread_cancel` semantics and cancellation points

### Sources

- https://man7.org/linux/man-pages/man3/pthread_cancel.3.html
- https://man7.org/linux/man-pages/man7/pthreads.7.html
- https://pubs.opengroup.org/onlinepubs/9699919799/functions/V2_chap02.html
  (section 2.9.5, Thread Cancellation)
- https://pubs.opengroup.org/onlinepubs/9699919799/functions/pthread_cancel.html
- https://pubs.opengroup.org/onlinepubs/9699919799/functions/pthread_setcancelstate.html
- https://man7.org/linux/man-pages/man3/pthread_setcancelstate.3.html
- https://man7.org/linux/man-pages/man3/pthread_cleanup_push.3.html
- https://man7.org/linux/man-pages/man3/pthread_join.3.html
- https://raw.githubusercontent.com/bminor/glibc/master/nptl/sem_waitcommon.c

### What was learned

- New threads start with cancellation enabled and type deferred; a deferred
  cancellation request is acted on only when the thread next calls a
  cancellation point. `pthread_cancel` returns 0 or an error number (`ESRCH`)
  and never `EINTR`; it only queues the request, and "joining with a thread is
  the only way to know that cancellation has completed". The joined status of
  a cancelled thread is `PTHREAD_CANCELED`.
- When the request is acted on: cleanup handlers run (LIFO), then
  thread-specific-data destructors, then the thread terminates.
- POSIX 2.9.5 "shall occur" list (confirmed on both the Open Group page and
  `pthreads(7)`): `sem_wait`, `sem_timedwait`, `sleep`, `nanosleep`,
  `usleep`, `pthread_join`, `pthread_cond_wait`, `write`. "May occur" list:
  `printf`, `fprintf`, `vfprintf`, `fputs`, `puts`, `fflush`. `sem_post` is in
  neither list.
- Side effects of cancelling a thread suspended in a cancellation point are
  "the same as the side effects that may be seen in a single-threaded program
  when a call to a function is interrupted by a signal and the given function
  returns [EINTR]", and they occur before cleanup handlers run. For
  `sem_wait` that means the count is not consumed. glibc's implementation
  confirms it: `__new_sem_wait_slow64` does `pthread_cleanup_push
  (__sem_wait_cleanup, sem)` before blocking, the cleanup only un-registers the
  waiter ("Stop being registered as a waiter"), and the token is taken only in
  the compare-and-swap branch that cancellation never reaches.
- A lock held at the moment of cancellation is never released unless a cleanup
  handler releases it; `pthread_cleanup_push(3)` exists exactly so a handler
  can "unlock a mutex so that it becomes available to other threads". POSIX
  RATIONALE for `pthread_setcancelstate` recommends disabling cancellation on
  entry to a sequence that must not be cut short and restoring the old state on
  exit. Asynchronous cancellation is not usable here: only `pthread_cancel`,
  `pthread_setcancelstate` and `pthread_setcanceltype` are async-cancel-safe.

### Adopted in this project

- Deferred cancellation (the default) is left in place; nothing calls
  `pthread_setcanceltype`.
- Critical sections guarded by `connected_lock` and `id_lock` contain only
  an integer compare and increment/decrement: no `printf`, no `sleep`, no
  `sem_wait` on another semaphore. Therefore no cancellation point can ever
  fire while a binary semaphore is held, and the lock cannot be orphaned.
- The `operators` token is deliberately held across `sleep(QUESTION_SECONDS)`
  (the spec requires that). A thread cancelled there dies without posting the
  token; that is harmless because by then every other thread is also being
  cancelled, and a thread blocked in `sem_wait(&operators)` is itself at a
  cancellation point. After the join loop no waiter exists and `sem_destroy`
  is safe.
- Termination is `pthread_cancel(tid[i])` then `pthread_join(tid[i], NULL)`
  for each `i`, so every cancellation is known to have completed before the
  semaphores are destroyed.

### Pitfalls avoided

- A cancellation point inside a `connected_lock`/`id_lock` critical section,
  which would leave the lock taken forever and hang every later thread at its
  own `sem_wait`, including threads main is trying to cancel.
- Assuming `pthread_cancel` returning 0 means the thread is gone; only
  `pthread_join` proves it.
- Asynchronous cancellation, which would make even the semaphore calls unsafe.

## 3. Lost or corrupted stdout output when threads are cancelled

### Sources

- https://man7.org/linux/man-pages/man3/setvbuf.3.html
- https://sourceware.org/glibc/manual/latest/html_node/Buffering-Concepts.html
- https://sourceware.org/glibc/manual/latest/html_node/Flushing-Buffers.html
- https://man7.org/linux/man-pages/man3/exit.3.html
- https://sourceware.org/glibc/manual/latest/html_node/Termination-Internals.html
- https://man7.org/linux/man-pages/man3/flockfile.3.html
- https://sourceware.org/glibc/manual/latest/html_node/Streams-and-Threads.html
- https://raw.githubusercontent.com/bminor/glibc/master/sysdeps/nptl/stdio-lock.h
- https://raw.githubusercontent.com/bminor/glibc/master/sysdeps/pthread/tst-cancel9.c
- https://man7.org/linux/man-pages/man7/pthreads.7.html

### What was learned

- Buffering: a stream on an interactive device starts line buffered; every
  other stream (pipe, file, the e2e harness) starts fully buffered. A line
  buffered stream is flushed at each newline; a fully buffered one only when
  the buffer fills, on `fflush`, on `fclose`, or on `exit`.
- `setvbuf(stream, NULL, _IOLBF, 0)` switches the mode and lets glibc allocate
  the buffer; it "may be used only after opening a stream and before any other
  operations have been performed on it". It returns nonzero on failure.
- `exit()` (and returning from `main`) flushes and closes all open stdio
  streams; `_exit` runs no cleanup and the glibc manual notes that streams
  "are not flushed automatically when the process terminates" by that route.
  `exit()` is not thread-safe (MT-Unsafe race:exit), so only one thread may
  ever call it.
- Thread safety of stdio: "The stdio functions are thread-safe"; each `FILE`
  has a recursive lock taken for the duration of each call, so one `printf`
  of one line is never interleaved with another thread's. POSIX requires this
  per-operation atomicity.
- Cancellation and stdio in glibc: `printf` is a "may be" cancellation point
  in POSIX and in practice is one in glibc because it calls `write`
  (glibc's own test `tst-cancel9.c` relies on this: "fprintf() uses write()
  which is a cancellation point"). The stream lock is nevertheless not
  leaked: glibc takes it through `_IO_acquire_lock`, which declares the
  `FILE *` with `__attribute__((cleanup (_IO_acquire_lock_fct)))` and so
  `_IO_funlockfile` runs when cancellation unwinds the frame (the macro is
  compiled only with `__EXCEPTIONS`, i.e. unwinding, enabled). So a thread
  cancelled inside `printf` cannot deadlock other printers or `exit`'s flush.
- What can still happen: with line buffering the whole line is handed to one
  `write`. If cancellation lands on that `write`, POSIX's `EINTR`-equivalence
  rule says the data either went out or is still in the buffer; whatever is
  still buffered is written by `exit()`. No line is lost, but a line can be
  emitted late, after lines from other threads.

### Adopted in this project

- `main` calls `setvbuf(stdout, NULL, _IOLBF, 0)` as its first stdout
  operation and checks the result, so piped output appears line by line and
  nothing sits in a 4 KiB buffer while 200 threads are cancelled.
- Each thread prints a complete line with one `printf` call ending in `\n`,
  so the stream lock guarantees lines are never interleaved.
- All printing goes through one helper that disables cancellation around the
  `printf` (`pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old)` before,
  restore `old` after). This is the safest practical option for this program:
  it costs three lines, it makes `sem_wait` and `sleep` the only cancellation
  points in a call thread, and it removes even the "late line" case above.
  Both guarantees above (lock released, data flushed by `exit`) hold without
  it, so the program is also correct on a libc that lacks the cleanup
  attribute; the helper just makes the output trace deterministic.
- Only `main` ever calls `exit`/returns, after every thread is joined, so the
  final flush runs with no concurrent writer. `_exit` and `abort` are not
  used anywhere.

### Pitfalls avoided

- Fully buffered stdout under a pipe making the e2e harness see nothing until
  exit, and losing everything if the process ever died by `_exit` or signal.
- Calling `setvbuf` after the first `printf` (undefined by the standard's
  ordering rule).
- Building lines from several `printf` calls, which the per-call lock does not
  protect; or calling `fflush` from many threads as a substitute for correct
  buffering.
- Relying on `write(2)` directly to dodge stdio, which would bypass the
  `_IOLBF` setting and still be a cancellation point.

## 4. Why `next_id++` is a data race

### Sources

- https://port70.net/~nsz/c/c11/n1570.html (C11 draft, 5.1.2.4)
- https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/concurrency-con/con43-c
- https://man7.org/linux/man-pages/man3/sem_wait.3.html

### What was learned

- C11 5.1.2.4p4: two evaluations conflict if one modifies a memory location
  and the other reads or modifies it. p25: an execution "contains a data race
  if it contains two conflicting actions in different threads, at least one of
  which is not atomic, and neither happens before the other. Any such data
  race results in undefined behavior." C99 has no threads in its memory model
  at all, so under `-std=c99` the only ordering guarantees come from POSIX
  synchronisation functions; the C11 wording is the clearest statement of why.
- `next_id++` compiles to load, add, store. Two threads can both load the same
  value and both store `value + 1`: two callers with one id, one id skipped.
  CERT CON43-C shows the identical bug with `+=` on a `volatile` counter and
  explains that `volatile` prevents only caching/elimination, not
  interleaving. The compliant solution is a lock around the read-modify-write.
- `sem_wait`/`sem_post` are POSIX synchronisation operations; a value written
  before `sem_post` is visible to the thread that returns from the matching
  `sem_wait`, which is exactly the happens-before edge the increment needs.

### Adopted in this project

- `static int next_id = 1;` at file scope and a binary semaphore
  `id_lock`. In `phonecall`: `sem_wait(&id_lock); id = next_id++;
  sem_post(&id_lock);` with `id` an ordinary automatic `int` local to the
  thread function, as the spec words it ("incrementing a global variable
  called next_id and assigning it to the id variable inside the thread
  function"). The answer to the spec's "do you need synchronization here?" is
  yes, and this is it.
- `main` does not pass ids through the `void *` argument; the id is produced
  inside the thread, as required, so the lock is the only correct mechanism.

### Pitfalls avoided

- Unsynchronised `next_id++` (duplicate or skipped ids, undefined behaviour).
- `volatile` as a substitute for a lock.
- Assigning the id in `main` before `pthread_create`, which would satisfy the
  uniqueness but violate the spec's placement of the increment.

## 5. `static` at file scope versus block scope

### Sources

- https://en.cppreference.com/w/c/language/storage_duration
- The spec's own declarations (`static sem_t connected_lock; ... static int
  connected = 0;`) and the rubric line "The static modifier is used properly
  for both thread local variables as well as any global variables".

### What was learned

- `static` at file scope gives static storage duration and internal linkage:
  the object exists once for the whole program and its name is invisible to
  other translation units.
- `static` at block scope gives static storage duration with no linkage: one
  object for the whole program, initialised once, shared by every caller of
  the function, and therefore shared by every thread executing it.
- An object with automatic storage duration is created on each entry to its
  block; each thread has its own stack, so an automatic local in the thread
  function is private to that thread.

### Adopted in this project

- Every file-scope object is `static`: the spec's semaphores and counters,
  `next_id`, `id_lock`, and the thread-id array if it is not local to `main`.
  Every function except `main` is `static`.
- The caller's `id` is a plain automatic `int` inside `phonecall`, never
  `static`. A `static int id` inside the function would be one variable shared
  by all 200 threads: the last writer would overwrite everyone's id and the
  per-caller trace the rubric asks for would be wrong.
- Reading of the rubric sentence: "used properly for ... thread local
  variables" means knowing when not to use it; "proper" use for a thread's
  own state is the absence of `static`, and "proper" use for globals is its
  presence. `docs/design.md` records this interpretation.

### Pitfalls avoided

- `static` on the per-thread `id` (shared state masquerading as a local).
- Non-`static` globals, which would have external linkage for no reason.
- `_Thread_local` as an alternative: it is C11 and the floor is `-std=c99`.

## 6. `sleep()` in threads

### Sources

- https://man7.org/linux/man-pages/man3/sleep.3.html
- https://pubs.opengroup.org/onlinepubs/9699919799/functions/sleep.html
- https://man7.org/linux/man-pages/man2/nanosleep.2.html
- https://man7.org/linux/man-pages/man7/feature_test_macros.7.html
- Local headers: `/usr/include/unistd.h`, `/usr/include/time.h` (glibc 2.43)

### What was learned

- POSIX: `sleep` "shall cause the calling thread to be suspended", and "in
  multi-threaded programs, sleep() shall not make use of SIGALRM". The
  historical alarm-based implementation is explicitly "not appropriate for
  multi-threaded programs". On Linux, `sleep` is implemented with
  `nanosleep`, and `nanosleep` "does not interact with signals".
- Return value: 0 when the full time elapsed, otherwise the unslept seconds
  if a signal handler interrupted it. `nanosleep` instead returns -1/`EINTR`
  and writes the remaining time to `rem`, which makes resuming easier, and
  needs `_POSIX_C_SOURCE >= 199309L`.
- `sleep` is declared unconditionally in this glibc's `unistd.h`;
  `nanosleep` in `time.h` is behind `__USE_POSIX199309`. Verified locally:
  with plain `-std=c99` `nanosleep` is an implicit declaration error while
  `sleep` compiles; with `-D_POSIX_C_SOURCE=200809L` both compile.
- Both `sleep` and `nanosleep` are required cancellation points (section 2),
  which is what makes "cancel the thread while it waits" work at all.

### Adopted in this project

- `sleep(1)` for the busy-line retry and `sleep(QUESTION_SECONDS)` with
  `QUESTION_SECONDS` = 1 for the question, matching the spec's prose; the
  spec's "sleep(3)" aside is read as the manual section number and the README
  notes it. The timer thread sleeps `debate_seconds` once.
- No signal handlers are installed and `alarm` is never used, so `sleep`
  cannot return early; the return value is still read and, if nonzero, the
  thread simply continues (the simulation is approximate by design).
- `nanosleep` is not needed; the compile line still defines
  `_POSIX_C_SOURCE=200809L` so either would be declared.

### Pitfalls avoided

- Mixing `alarm`/`SIGALRM` with `sleep` (undefined results).
- Assuming `sleep` suspends the whole process (it is per-thread).
- Compiling under `-std=c99` without a feature macro and discovering a POSIX
  function is undeclared only on the course VM.

## 7. Argument parsing with `strtol`

### Sources

- https://man7.org/linux/man-pages/man3/strtol.3.html

### What was learned

- `strtol` skips leading whitespace, accepts an optional sign, and stops at
  the first non-digit; `*endptr` points there. If no digits were converted,
  `*endptr == nptr` and 0 is returned. On overflow it returns `LONG_MAX` or
  `LONG_MIN` with `errno = ERANGE`. Since 0, `LONG_MAX` and `LONG_MIN` are
  also legitimate results, the return value alone cannot signal failure: set
  `errno = 0` before the call and test `errno`, `endptr == nptr` and
  `*endptr != '\0'` afterwards. `EINVAL` for "no conversion" is
  implementation-specific and must not be relied on.

### Adopted in this project

- `parse_debate_seconds(const char *text, long *out)`: `errno = 0`;
  `strtol(text, &end, 10)`; reject when `end == text` (empty or no digits),
  `*end != '\0'` (trailing garbage such as `10s`), `errno == ERANGE`
  (overflow), or `value <= 0` (zero and negatives). Leading whitespace is
  rejected explicitly by requiring the first character to be a digit, so
  `" 10"` is an error rather than silently accepted. A value above `INT_MAX`
  is rejected because `sleep` takes `unsigned int` and the e2e harness bounds
  it anyway.
- `main` with `argc != 2` or a failed parse prints a usage line to `stderr`
  and returns `EXIT_FAILURE` before creating any thread or semaphore.
- The parser is a pure function so the unit tests cover every branch.

### Pitfalls avoided

- `atoi` (no error reporting; `atoi("abc")` is 0 and `atoi("10abc")` is 10).
- Testing only the return value and accepting `0` or `LONG_MAX` as valid.
- Accepting `-5` or `0`, which would make the timer return immediately or
  pass a negative to `unsigned int sleep`.

## 8. `pthread_create` in a loop, join after cancel, and why not detach

### Sources

- https://man7.org/linux/man-pages/man3/pthread_create.3.html
- https://man7.org/linux/man-pages/man3/pthread_join.3.html
- https://man7.org/linux/man-pages/man3/pthread_detach.3.html
- https://man7.org/linux/man-pages/man3/pthread_cancel.3.html

### What was learned

- `pthread_create`, `pthread_join`, `pthread_cancel` and `pthread_detach`
  return 0 or an error number; they do not set `errno`. `pthread_create` can
  fail with `EAGAIN` (thread limit, `RLIMIT_NPROC`), so creating 200 threads
  is not guaranteed and must be checked.
- "Either pthread_join(3) or pthread_detach() should be called for each
  thread that an application creates"; an unjoined joinable thread is a
  zombie that holds resources. A detached thread "can't be joined with
  pthread_join(3) or be made joinable again", and joining it fails with
  `EINVAL`. Joining a thread twice, or two threads joining the same thread, is
  undefined.
- `pthread_join` on a cancelled thread returns 0 with `*retval ==
  PTHREAD_CANCELED`, and is the only way to know the cancellation has
  finished.

### Adopted in this project

- `pthread_t calls[NUM_CALLS]` (200) filled by one `for` loop over
  `pthread_create(&calls[i], NULL, phonecall, NULL)`. A creation failure is
  reported with `strerror(rc)` on `stderr`; the threads already created are
  cancelled and joined, the semaphores destroyed, and `EXIT_FAILURE` returned.
- A separate timer thread is created and joined; its return ends the debate.
- Shutdown order: for each call thread `pthread_cancel` then `pthread_join`,
  then `sem_destroy` on all three semaphores, then `return EXIT_SUCCESS`.
- No thread is detached. The rubric says "created, detached, and joined
  properly"; the proper choice here is to join every thread, because the
  semaphores can only be destroyed once no thread can touch them, and only a
  join proves that. Detaching would make the join impossible and would leave
  `sem_destroy` racing against threads that may still be blocked on the
  semaphore. The README's requirements map explains that "detached" is
  satisfied by not detaching, with this reason.

### Pitfalls avoided

- `perror` after a pthread call (it reads `errno`, which the call did not
  set); the code uses `strerror(rc)`.
- Ignoring `pthread_create` failure and later joining an uninitialised
  `pthread_t`.
- Destroying semaphores or returning from `main` while threads are alive.
- Cancelling without joining, which leaves the completion unknown.

## 9. `-pthread` and `_POSIX_C_SOURCE=200809L` under `-std=c99`

### Sources

- https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html
- https://gcc.gnu.org/onlinedocs/gcc/Preprocessor-Options.html
- https://man7.org/linux/man-pages/man7/feature_test_macros.7.html
- https://man7.org/linux/man-pages/man7/sem_overview.7.html
- Local: `/usr/include/features.h`, gcc 16.2.1 experiments

### What was learned

- gcc documents `-pthread` twice: as a preprocessor option ("Define
  additional macros required for using the POSIX threads library") and as a
  link option ("Link with the POSIX threads library"), and both pages say to
  "use this option consistently for both compilation and linking". Verified
  locally: at compile time it adds `#define _REENTRANT 1`; at link time it
  adds `-lpthread`. `sem_overview(7)` likewise says programs using semaphores
  "must be compiled with cc -pthread".
- `-std=c99` defines `__STRICT_ANSI__`, and glibc then defines none of the
  default feature macros, so POSIX declarations disappear from the headers.
  Feature macros must be defined before any header is included, which is why
  the Makefile puts `-D_POSIX_C_SOURCE=200809L` on the command line rather
  than in the source. `200809L` selects POSIX.1-2008 and, because the tests
  are `>=`, also everything from the 1993 real-time and 1995 threads levels.
- `_REENTRANT` is "obsolete; equivalent to _POSIX_C_SOURCE=199506L" and only
  ever raises the level (`features.h`). So `-pthread` alone happens to expose
  `nanosleep` and `sem_*` under `-std=c99`, but that is a side effect of a
  compatibility shim, not a documented contract; the explicit macro is.

### Adopted in this project

- `CFLAGS` carry `-std=c99 -D_POSIX_C_SOURCE=200809L -pthread` plus the
  warning set; `LDFLAGS` carry `-pthread`. The flat `dist/Makefile` uses the
  same flags so the Gradescope build is identical.
- The source defines no feature macro of its own.

### Pitfalls avoided

- `-lpthread` only on the link line (works on modern glibc, where libpthread
  merged into libc, but omits `_REENTRANT` and is not what gcc documents).
- `#define _POSIX_C_SOURCE` after an `#include`, which has no effect.
- Relying on `_REENTRANT` from `-pthread` to pull in POSIX declarations.
