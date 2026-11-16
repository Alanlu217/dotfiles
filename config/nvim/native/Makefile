# Out-of-tree build: sources may live in a read-only config dir (e.g. NixOS);
# artifacts go to BUILD_DIR (Neovim passes stdpath("data")/native).
#
# Portable across glibc, musl (Alpine, Void-musl) and Android's bionic
# (Termux). Only C11 + POSIX.1-2008 is used; _DEFAULT_SOURCE is defined here,
# in one place, rather than in each file.
#
#   make              build the library
#   make test         build and run the tests
#   make info         show the compiler, target triple and library name
#   make check-libc   run the tests with every compiler found (cc, gcc, clang,
#                     musl-gcc), each in its own build dir

# `make` predefines CC=cc; if there is no `cc` (some minimal images), pick the
# first compiler that exists. An explicit CC=... always wins.
ifeq ($(origin CC),default)
  CC := $(firstword $(foreach c,cc gcc clang,$(if $(shell command -v $(c) 2>/dev/null),$(c))) cc)
endif

BUILD_DIR ?= build
CFLAGS    ?= -O2
WARN      := -Wall -Wextra -Wpedantic -Wshadow
CFLAGS    += -std=c11 -D_DEFAULT_SOURCE $(WARN) -fPIC -fvisibility=hidden -I. -MMD -MP

# All C lives in this directory; test_*.c is the test driver, not the library.
SRC  := $(filter-out test_%.c,$(wildcard *.c))
OBJ  := $(SRC:%.c=$(BUILD_DIR)/obj/%.o)

# Android/Termux reports "Linux" and uses .so like other ELF systems.
ifeq ($(shell uname -s),Darwin)
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

$(BUILD_DIR)/obj/%.o: %.c | $(BUILD_DIR)/obj
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/obj:
	mkdir -p $@

$(TEST): test_core.c $(OBJ)
	$(CC) $(CFLAGS) -g -O0 test_core.c $(OBJ) -o $@

test: $(TEST)
	$(TEST)

info:
	@echo "CC     = $(CC)"
	@echo "target = $$($(CC) -dumpmachine 2>/dev/null || echo unknown)"
	@echo "lib    = $(LIB)"

# Typical triples: x86_64-linux-gnu (glibc), x86_64-linux-musl (musl),
# aarch64-linux-android (Termux/bionic).
CHECK_CCS ?= cc gcc clang musl-gcc
check-libc:
	@ran=0; seen=""; \
	for c in $(CHECK_CCS); do \
	  command -v $$c >/dev/null 2>&1 || continue; \
	  t=$$($$c -dumpmachine 2>/dev/null || echo unknown); \
	  case " $$seen " in *" $$c:$$t "*) continue;; esac; \
	  seen="$$seen $$c:$$t"; \
	  echo "== $$c ($$t)"; \
	  $(MAKE) -s CC=$$c BUILD_DIR=$(BUILD_DIR)/check-$$c clean test || exit 1; \
	  ran=$$((ran + 1)); \
	done; \
	[ $$ran -gt 0 ] || { echo "no C compiler found" >&2; exit 1; }; \
	echo "check-libc: $$ran compiler(s) passed"

clean:
	rm -rf $(BUILD_DIR)

-include $(OBJ:.o=.d)
.PHONY: all test info check-libc clean
