# Shared rules for a SCAM userspace application.
#
# An application's sw/Makefile needs only:
#
#     APP       := myapp
#     SCAM_ROOT ?= ../../..
#     include $(SCAM_ROOT)/sw/common/app.mk
#
# Every *.c in the application's sw/ directory is compiled together with the
# helpers in sw/common/. The compiler comes from the SDK environment:
#
#     source <sdk>/environment-setup-cortexa72-cortexa53-xilinx-linux
#     make
#
# or run 'make app-<name> SCAM_SDK=<sdk>' from the repository root.
# 'make CC=gcc' gives a native build for testing off the board.

SCAM_ROOT ?= ../../..
override SCAM_ROOT := $(abspath $(SCAM_ROOT))
COMMON := $(SCAM_ROOT)/sw/common

# Optional BITSTREAM= / BINARY= overrides.
-include $(CURDIR)/../app.conf

APP     ?= $(notdir $(abspath $(CURDIR)/..))
BINARY  ?= yeet-data-$(APP)
OUT_DIR ?= $(SCAM_ROOT)/build/apps/$(APP)

# Make's built-in CC is the host compiler, which cannot build for the board.
ifeq ($(origin CC),default)
  ifdef CROSS_COMPILE
    CC := $(CROSS_COMPILE)gcc
  else
    $(error No cross compiler. Source the SDK environment-setup file, or run 'make app-$(APP) SCAM_SDK=<installed sdk dir>' from the SCAM root. See docs/adding-an-app.md)
  endif
endif

CFLAGS ?= -O2 -Wall

SRCS := $(wildcard $(CURDIR)/*.c) $(wildcard $(COMMON)/*.c)
HDRS := $(wildcard $(CURDIR)/*.h) $(wildcard $(COMMON)/*.h)
OUT  := $(OUT_DIR)/$(BINARY)

all: $(OUT)

$(OUT): $(SRCS) $(HDRS)
	@mkdir -p $(OUT_DIR)
	$(CC) $(CFLAGS) -I$(COMMON) -o $@ $(SRCS) $(LDFLAGS) $(LDLIBS)

clean:
	rm -f $(OUT)

.PHONY: all clean
