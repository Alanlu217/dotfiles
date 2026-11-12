# Out-of-tree build: sources may live in a read-only config dir (e.g. NixOS);
# artifacts go to BUILD_DIR (Neovim passes stdpath("data")/native).
CC        ?= cc
BUILD_DIR ?= build
CFLAGS    ?= -O2
WARN      := -Wall -Wextra -Wpedantic -Wshadow
CFLAGS    += -std=c11 $(WARN) -fPIC -fvisibility=hidden -Iinclude -Isrc -MMD -MP

SRC  := $(wildcard src/*.c)
OBJ  := $(SRC:src/%.c=$(BUILD_DIR)/obj/%.o)

ifeq ($(shell uname),Darwin)
  EXT := dylib
else
  EXT := so
endif
LIB  := $(BUILD_DIR)/libnvcore.$(EXT)
TEST := $(BUILD_DIR)/test_core

all: $(LIB)

# Link to a temp name then rename: replacing a mapped .so in place can crash a
# running Neovim, while rename gives the new file a fresh inode.
$(LIB): $(OBJ)
	$(CC) -shared -o $@.tmp $(OBJ)
	mv -f $@.tmp $@

$(BUILD_DIR)/obj/%.o: src/%.c | $(BUILD_DIR)/obj
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/obj:
	mkdir -p $@

$(TEST): tests/test_core.c $(OBJ)
	$(CC) $(CFLAGS) -g -O0 tests/test_core.c $(OBJ) -o $@

test: $(TEST)
	$(TEST)

clean:
	rm -rf $(BUILD_DIR)

-include $(OBJ:.o=.d)
.PHONY: all test clean
