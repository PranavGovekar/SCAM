CC      ?= gcc
CFLAGS  ?= -O2 -Wall
LDFLAGS ?=

OUT = yeet-data-tdc

all: $(OUT)

$(OUT): yeet-data-tdc.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(OUT)

.PHONY: all clean
