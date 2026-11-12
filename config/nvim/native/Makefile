CC = cc
CFLAGS = -O3 -fPIC -shared
TARGET_DIR = bin

SRC = utils.c fuzzy.c

TARGET = $(TARGET_DIR)/core.so
FFI_HEADER_NAME = common_ffi.h
FFI_HEADER = $(TARGET_DIR)/$(FFI_HEADER_NAME)

OS := $(shell uname)
ifeq ($(OS), Darwin)
    TARGET = $(TARGET_DIR)/core.dylib
endif

all: $(TARGET_DIR) $(TARGET) $(FFI_HEADER)

$(TARGET_DIR):
	mkdir -p $(TARGET_DIR)

$(TARGET): $(SRC) common.h
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET)

$(FFI_HEADER): common.h | $(TARGET_DIR)
	$(CC) -E -P common.h -o $(FFI_HEADER)

test: test.c $(SRC) common.h
	$(CC) -g -O0 test.c $(SRC) -o $(TARGET_DIR)/run_tests
	./$(TARGET_DIR)/run_tests $(arg)

clean:
	rm -rf $(TARGET_DIR) run_tests test

.PHONY: all test clean
