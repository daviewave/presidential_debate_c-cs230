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

int main(void) {
    test_parse_debate_seconds_accepts_positive_integers();
    test_parse_debate_seconds_rejects_bad_input();
    CHECK_REPORT("test_presidential_debate");
}
