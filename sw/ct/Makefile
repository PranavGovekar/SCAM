CC      ?= aarch64-xilinx-linux-gcc
CFLAGS  ?= -O2 -Wall -I../common
LDFLAGS ?=

SRC = yeet-data-ct.c ../common/reg_io.c ../common/udp.c ../common/args.c ../common/i2c_dac.c
OUT = yeet-data-ct

all: $(OUT)

$(OUT): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(OUT)

.PHONY: all clean
