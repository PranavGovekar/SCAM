# sw/common

Shared C headers and helpers used by both userspace applications.

| File | Purpose |
| :-- | :-- |
| `reg_io.h`, `reg_io.c` | `/dev/mem` mapping + register read/write helpers. Includes the fixed AXI address map. |
| `udp.h`, `udp.c`       | Minimal UDP sender used by both applications. |
| `args.h`, `args.c`     | Shared `-n`/`-t`/`-v` CLI parsing. |
| `i2c_dac.h`, `i2c_dac.c` | DAC5578 threshold setup over PS I2C1 (`/dev/i2c-1`). |

`app.mk` holds the build rules shared by every application's `sw/Makefile`. It
compiles all `*.c` files here directly into each application binary. There is
no shared library in the source tree — inside PetaLinux the `yeet-data-common`
recipe packages them once and the baked-in apps link against the resulting
`libscam_common.a`.

## Adding a helper

Add the `.h`/`.c` pair here; `app.mk` picks it up automatically. For the
PetaLinux image, also list the new files in `yeet-data-common.bb` (`SRC_URI`,
`do_compile`, `do_install`).
