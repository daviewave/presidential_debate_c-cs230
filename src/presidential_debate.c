/*
 * presidential_debate.c: 200 callers compete for 5 phone lines and 2 operators
 * for the length of a debate given in seconds on the command line.
 * Design rationale: docs/design.md.
 */
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    MESSAGE_CAPACITY = 128    /* longest template plus a caller id, with room */
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

/* The spec's templates: the text after "Thread <id> " for each CallStage. */
static const char *const STAGE_MESSAGES[STAGE_COUNT] = {
    "is attempting to connect ...",
    "connects to an available line, call ringing ...",
    "is speaking to an operator.",
    "has proposed a question for candidates! The operator has left ...",
    "has hung up!"
};

static sem_t connected_lock;      /* binary semaphore: the only guard of connected */
static sem_t operators;           /* counting semaphore: one unit per free operator */
static sem_t id_lock;             /* binary semaphore: the only guard of next_id */
static int NUM_OPERATORS = 2;
static int NUM_LINES = 5;
static int connected = 0;         /* callers currently holding a phone line */

/* Report a failed call on stderr and end the process; error is an errno value. */
static void die(const char *what, int error) {
    fprintf(stderr, "presidential_debate: %s: %s\n", what, strerror(error));
    exit(EXIT_FAILURE);
}

/* die() with errno when failed is non-zero: for calls that return -1 and set errno. */
static void check_errno(int failed, const char *what) {
    if (failed) {
        die(what, errno);
    }
}

/* die() when error is non-zero: for pthread calls, which return the error number. */
static void check_error(int error, const char *what) {
    if (error != 0) {
        die(what, error);
    }
}

/* sem_init all three semaphores with their starting values. */
static void initialize_semaphores(void) {
    check_errno(sem_init(&connected_lock, 0, 1) == -1, "sem_init connected_lock");
    check_errno(sem_init(&operators, 0, (unsigned int)NUM_OPERATORS) == -1,
                "sem_init operators");
    check_errno(sem_init(&id_lock, 0, 1) == -1, "sem_init id_lock");
}

/* sem_destroy all three semaphores; legal only once no thread can touch them. */
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

/* Print the usage line on stderr. */
static void print_usage(const char *program) {
    fprintf(stderr, "Usage: %s <debate seconds>\n", program);
}

/*
 * Validate text as a debate length: decimal digits only, 1..INT_MAX.
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

/*
 * Render the trace line for one stage of a call into buffer (no newline).
 * @return the length written, or -1 if capacity was too small.
 */
static int format_call_message(char *buffer, size_t capacity, int id, CallStage stage) {
    int length = snprintf(buffer, capacity, "Thread %d %s", id, STAGE_MESSAGES[stage]);
    if (length < 0 || (size_t)length >= capacity) {
        return -1;
    }
    return length;
}

/*
 * Print one trace line for the caller. Cancellation is off while printing so
 * a cancelled thread never dies inside stdio (docs/design.md section 4).
 */
static void announce(int id, CallStage stage) {
    char message[MESSAGE_CAPACITY];
    int previous_state;
    int ignored_state;
    if (format_call_message(message, sizeof message, id, stage) < 0) {
        die("format_call_message", EOVERFLOW);
    }
    check_error(pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_state),
                "pthread_setcancelstate");
    check_errno(puts(message) == EOF, "puts");
    check_error(pthread_setcancelstate(previous_state, &ignored_state),
                "pthread_setcancelstate");
}

int main(int argc, char *argv[]) {
    unsigned int seconds;
    if (argc != 2 || !parse_debate_seconds(argv[1], &seconds)) {
        print_usage(argc > 0 ? argv[0] : "presidential_debate");
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
