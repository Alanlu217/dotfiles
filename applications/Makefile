OUT_DIR := $(HOME)/.local/share/applications

SRC := $(wildcard *.desktop)
OUT := $(foreach src,$(SRC),$(OUT_DIR)/$(src))

.PHONY: all
all: $(OUT)

.PHONY: $(OUT)
$(OUT): $(OUT_DIR)/%: %
	@mkdir -p $(OUT_DIR)
	ln -s "$(abspath $<)" "$@"

.PHONY: clean
clean:
	@for i in $(OUT); do \
		echo rm -rf $$i; \
		rm -rf $$i; \
	done
