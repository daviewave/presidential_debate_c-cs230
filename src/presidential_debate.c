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

int main(int argc, char *argv[]) {
    unsigned int seconds;
    if (argc != 2 || !parse_debate_seconds(argv[1], &seconds)) {
        print_usage(argc > 0 ? argv[0] : "presidential_debate");
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
