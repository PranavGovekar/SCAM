CC      ?= gcc
CFLAGS  ?= -O2 -Wall
LDFLAGS ?=

OUT = yeet-data-ct

all: $(OUT)

$(OUT): yeet-data-ct.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(OUT)

.PHONY: all clean
