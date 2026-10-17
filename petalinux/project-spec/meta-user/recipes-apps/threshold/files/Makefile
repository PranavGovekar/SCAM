CC      ?= gcc
CFLAGS  ?= -O2 -Wall
LDFLAGS ?=

OUT = threshold

all: $(OUT)

$(OUT): threshold.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

clean:
	rm -f $(OUT)

.PHONY: all clean
