OS := $(shell uname)
CFLAGS = -O3 -fPIC -shared
TARGET_DIR = bin
SRC = $(wildcard *.c)

ifeq ($(OS), Darwin)
    TARGET = $(TARGET_DIR)/core.dylib
else
    TARGET = $(TARGET_DIR)/core.so
endif

FFI_HEADER = common_ffi.h

all: $(TARGET_DIR) $(TARGET) $(TARGET_DIR)/$(FFI_HEADER)

$(TARGET_DIR):
	mkdir -p $(TARGET_DIR)

$(TARGET): $(SRC) common.h
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET)

$(TARGET_DIR)/$(FFI_HEADER): common.h
	$(CC) -E -P common.h -o $(TARGET_DIR)/$(FFI_HEADER)

clean:
	rm -rf $(TARGET_DIR)

.PHONY: all clean
