CS230 Project 4: Threads and Synchronization, Presidential Debate
=================================================================

Overview
--------
presidential_debate.c simulates 200 callers phoning the CPD call centre
during a debate. Each caller is a pthread running the thread function
phonecall. The centre has 5 lines and 2 operators. A caller takes the next
caller id from the global next_id (under the binary semaphore id_lock),
announces the attempt, waits for a free line (the global counter connected,
guarded by the binary semaphore connected_lock, retried every second while
all 5 lines are busy), waits for an operator (the counting semaphore
operators, initialised to 2), spends one second proposing a question,
releases the operator, hangs up and releases the line. Every step prints
one line carrying the caller id. The debate length in seconds comes from
the command line; a timer thread sleeps that long, main joins it, then
cancels and joins every call thread, destroys the three semaphores and
exits 0. All of the code is in one file, presidential_debate.c.

Build and run
-------------
    make                        builds ./presidential_debate (flat bundle)
    ./presidential_debate 3     run a 3 second debate
    ./presidential_debate 10    run a 10 second debate
    ./presidential_debate 100   run a 100 second debate

The argument must be a positive whole number of seconds; anything else
prints "Usage: presidential_debate <debate seconds>" and exits 1.

The bundle builds with: gcc -std=c99 -D_POSIX_C_SOURCE=200809L -pthread
-Wall -Wextra -O2. -pthread is on the compile and link lines; the POSIX
feature macro exposes pthreads, semaphores and sleep under strict C99.

In the development repository the same code is built by a fuller Makefile
(make, make check for gcc -fanalyzer, make test for unit and end-to-end
tests, make test-long for the 20/50/100 s debates, make dist to produce
this bundle).

Requirements map
----------------
Every item below names the function (and line) in presidential_debate.c
that satisfies it.

Project Requirements
* Binary semaphores are used properly to protect critical regions of code.
  connected_lock guards every read and write of connected: try_claim_line
  (line 102: wait, compare, increment, post) and release_line (line 114:
  wait, decrement, post). id_lock guards next_id: phonecall (line 202,
  the three lines "wait_on(&id_lock); id = ++next_id; signal_on(&id_lock)").
  wait_on (line 85) and signal_on (line 94) are sem_wait (with EINTR retry)
  and sem_post with their results checked.
* Binary semaphores are used properly not to protect non-critical regions
  of code. Nothing but the touches of connected and next_id sits between a
  wait and a post on connected_lock or id_lock: no printing, no sleeping,
  no waiting on another semaphore. announce (line 160), sleep_fully
  (line 175) and the operator wait in propose_question (line 189) are all
  called outside those sections.
* A counting semaphore is used properly to restrict the use of resources
  (operators). operators is initialised to NUM_OPERATORS (2) in
  initialize_semaphores (line 70); propose_question (line 189) does
  sem_wait(operators), speaks, sleeps QUESTION_SECONDS, prints, then
  sem_post(operators), so at most two callers are ever with an operator.
* All semaphores are correctly initialized and destroyed.
  initialize_semaphores (line 70): sem_init(&connected_lock, 0, 1),
  sem_init(&operators, 0, 2), sem_init(&id_lock, 0, 1), each checked.
  destroy_semaphores (line 78): sem_destroy on all three, each checked,
  called from main only after every thread has been joined.
* A thread function exists and is implemented properly. phonecall
  (line 202) is the thread function given to pthread_create for every
  call; it follows the spec's step list (attempt, line, operator, question,
  completion, release, hang up) and returns NULL. debate_timer (line 218)
  is the timer thread function.
* Threads are created, detached, and joined properly. start_calls
  (line 225) creates NUM_CALLS (200) threads in a loop into the pthread_t
  array declared in main; run_debate (line 245) creates the timer thread
  and joins it; end_calls (line 234) cancels and then joins every call
  thread. No thread is detached, deliberately: a detached thread cannot be
  joined, and joining every thread is the only way to know that no thread
  can still touch a semaphore before sem_destroy. Every pthread_* return
  value is checked (check_error, line 63).
* A global variable next_id exists and is properly updated in the thread
  function and used to set the caller's id. static int next_id (line 47);
  phonecall (line 202) increments it inside the id_lock critical section
  and assigns the new value to its local variable id, which every message
  of that call then carries. Ids run 1..200.
* The phonecall thread properly updates the shared state for the number
  of connected callers in a critical section. try_claim_line (line 102)
  increments connected only when connected < NUM_LINES, inside
  connected_lock; release_line (line 114) decrements inside connected_lock;
  acquire_line (line 182) retries every BUSY_RETRY_SECONDS (1) while busy.
* The program prints properly formatted outputs with the caller's id.
  STAGE_MESSAGES (line 33) holds the spec's five templates;
  format_call_message (line 148) renders "Thread <id> <template>";
  announce (line 160) prints it. Output example for caller 7:
      Thread 7 is attempting to connect ...
      Thread 7 connects to an available line, call ringing ...
      Thread 7 is speaking to an operator.
      Thread 7 has proposed a question for candidates! The operator has left ...
      Thread 7 has hung up!
* The static modifier is used properly for both thread local variables as
  well as any global variables. Every file-scope object and every function
  except main is static (internal linkage): the semaphores, NUM_OPERATORS,
  NUM_LINES, connected, next_id, STAGE_MESSAGES. The caller id in phonecall
  is a plain automatic local (not static) so each thread has its own.

Design and Implementation
* Functions are declared and used properly: each function does one thing
  and has a header comment (see the function list in "Design notes").
* Data structures and data types: CallStage enum (line 23) names the five
  stages; STAGE_MESSAGES is indexed by it; pthread_t calls[NUM_CALLS] in
  main holds the thread ids; sem_t for the semaphores; unsigned int for the
  debate length because that is sleep()'s parameter type.
* Naming: snake_case functions named for what they do (try_claim_line,
  release_line, propose_question, end_calls), UPPER_SNAKE constants.
* Global variables are minimized: exactly the five the spec lists plus
  next_id and its lock, nothing else; all static and commented.
* Control flow: a single retry loop in acquire_line, create/cancel/join
  loops in start_calls and end_calls, no other loops; no unreachable code.
* Algorithms: the busy test is one compare in a five-line critical section;
  the operator limit is the counting semaphore itself.

Coding Style
* K&R braces on every if/while/for/function, four-space indentation,
  consistent spacing; compiled with -Wall -Wextra -Wpedantic -Wshadow
  -Wconversion -Werror and gcc -fanalyzer clean.

Comments
* Every function has a header comment giving its purpose and, where the
  signature does not say it, its parameters and return value. Every global
  whose purpose is not obvious from its name has a one-line comment.
  The file header points to the design notes.

Testing (spec's Testing section)
* 3 s and 10 s debates run under make test; 20 s, 50 s and 100 s under
  make test-long. Each run is checked for: exit status 0, finishing within
  the debate length plus 2 s, every output line matching a template, 200
  unique caller ids, each caller's lines in order, never more than 5 lines
  connected and never more than 2 operators busy at any point of the trace.

Design notes
------------
* Termination: main joins the timer thread, then pthread_cancel on each
  call thread, pthread_join on each, then sem_destroy, then return 0.
  sem_wait and sleep are POSIX cancellation points, which is where the
  unfinished threads are, so the cancel takes effect promptly; joining
  before destroying guarantees no thread is still inside sem_wait when the
  semaphore goes away.
* Printing with cancellation disabled: announce turns cancellation off
  around its one puts and back on afterwards, so a thread is never
  cancelled while inside stdio holding the stdout lock, and every line
  that starts printing is completed.
* stdout is set to line buffering (setvbuf, in main) so output written to a
  pipe or file appears line by line as events happen instead of sitting in
  a 4 KiB buffer until exit.
* "Simulate a question proposal by sleeping for 1 second (sleep(3))": the
  "(3)" is read as the manual section of the sleep library function, not a
  three-second argument, because the sentence says one second. The
  constant QUESTION_SECONDS (1) makes that one place to change.
* "has hung up!" is printed just before connected is decremented, while
  the spec's sketch lists the decrement first. The shared state is still
  updated in its critical section; moving the print makes the output trace
  a sound witness of the 5-line limit (the number of "connects" lines
  minus "hung up" lines never exceeds 5 at any point), the same
  print-then-release order the spec itself uses for operators.
* next_id needs synchronisation: id = ++next_id is a read-modify-write, and
  two threads interleaving it would share an id. id_lock serialises it.
* The busy case is silent: the spec's output has no "busy" line and 195
  waiting callers printing every second would drown the trace.

Function list (presidential_debate.c)
  die, check_errno, check_error        report a failed call and exit
  initialize_semaphores                sem_init x3
  destroy_semaphores                   sem_destroy x3
  wait_on, signal_on                   checked sem_wait (EINTR safe) / sem_post
  try_claim_line, release_line         the connected critical sections
  print_usage, parse_debate_seconds    command line handling
  format_call_message, announce        output lines with the caller id
  sleep_fully                          sleep that survives signals
  acquire_line, propose_question       the waiting steps of a call
  phonecall                            the call thread function
  debate_timer                         the timer thread function
  start_calls, end_calls, run_debate   thread creation, cancel/join, timing
  main                                 argument check, buffering, orchestration

Video: <VIDEO URL TO BE ADDED>
