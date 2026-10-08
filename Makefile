# Makefile for CS230 project 4, presidential_debate.
# Targets follow docs/conventions.md section 3: all, debug, test, test-long,
# check, run, dist, clean.

# make predefines CC as cc, so ?= alone would never pick gcc; override only
# make's own default and leave a CC given on the command line or environment.
ifeq ($(origin CC),default)
CC := gcc
endif

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
# not call look unused to the compiler; that one warning is waived there.
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

# all: the release binary in build/.
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

# check: gcc's static analyzer over every source; the objects land in
# build/check/ and are never linked.
$(BUILD_DIR)/check/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(BASE_FLAGS) $(WARN_FLAGS) -fanalyzer -c -o $@ $<

check: $(CHECK_OBJECTS)

# test: unit tests, the bad-argument cases and the 3 s and 10 s debates.
# test-long: the spec's 20 s, 50 s and 100 s debates (about three minutes).
test: $(PROGRAM)
	CC="$(CC)" TEST_CFLAGS="$(TEST_CFLAGS)" PROGRAM="$(PROGRAM)" test/run_tests.sh

test-long: $(PROGRAM)
	CC="$(CC)" TEST_CFLAGS="$(TEST_CFLAGS)" PROGRAM="$(PROGRAM)" test/run_tests.sh long

# run: a 3 second debate, the spec's first test case.
run: $(PROGRAM)
	$(PROGRAM) 3

# dist: the flat Gradescope bundle (source, README.txt, a generated flat
# Makefile), then a build inside it proves the bundle compiles on its own.
define DIST_MAKEFILE
# Flat Makefile for the Gradescope submission: builds presidential_debate here.
# make predefines CC as cc, so ?= alone would never pick gcc; override only
# make's own default and leave a CC given on the command line or environment.
ifeq ($(origin CC),default)
CC := gcc
endif
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
