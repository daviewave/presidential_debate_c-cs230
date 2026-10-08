/* Unit tests for src/presidential_debate.c via the include trick: the real
 * main becomes program_main and every static function is callable here. */
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
    CHECK(!parse_debate_seconds("3 ", &seconds));
    CHECK(!parse_debate_seconds(" 3", &seconds));
    CHECK(!parse_debate_seconds("+3", &seconds));
    CHECK(!parse_debate_seconds("0x10", &seconds));
    CHECK(!parse_debate_seconds("2147483648", &seconds));
    CHECK(!parse_debate_seconds("99999999999999999999", &seconds));
    CHECK(!parse_debate_seconds(NULL, &seconds));
    CHECK_EQ_INT(seconds, 42);
}

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

static void test_every_stage_has_a_message(void) {
    int stage;
    for (stage = 0; stage < STAGE_COUNT; stage++) {
        CHECK(STAGE_MESSAGES[stage] != NULL);
    }
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

static void test_critical_sections_release_the_lock(void) {
    int value = -1;
    initialize_semaphores();
    connected = NUM_LINES;
    CHECK(!try_claim_line());
    CHECK_EQ_INT(sem_getvalue(&connected_lock, &value), 0);
    CHECK_EQ_INT(value, 1);
    release_line();
    CHECK_EQ_INT(sem_getvalue(&connected_lock, &value), 0);
    CHECK_EQ_INT(value, 1);
    connected = 0;
    destroy_semaphores();
}

static void test_phonecall_takes_unique_ids_and_frees_its_line(void) {
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

static void test_constants_match_the_spec(void) {
    CHECK_EQ_INT(NUM_CALLS, 200);
    CHECK_EQ_INT(NUM_LINES, 5);
    CHECK_EQ_INT(NUM_OPERATORS, 2);
    CHECK_EQ_INT(QUESTION_SECONDS, 1);
    CHECK_EQ_INT(BUSY_RETRY_SECONDS, 1);
}

int main(void) {
    test_parse_debate_seconds_accepts_positive_integers();
    test_parse_debate_seconds_rejects_bad_input();
    test_format_call_message_matches_spec_templates();
    test_format_call_message_uses_the_given_id();
    test_format_call_message_reports_truncation();
    test_every_stage_has_a_message();
    test_semaphores_start_with_spec_values();
    test_try_claim_line_respects_num_lines();
    test_critical_sections_release_the_lock();
    test_phonecall_takes_unique_ids_and_frees_its_line();
    test_debate_timer_returns_after_the_given_seconds();
    test_constants_match_the_spec();
    CHECK_REPORT("test_presidential_debate");
}
