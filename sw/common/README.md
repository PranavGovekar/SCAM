# sw/common

Shared C headers and helpers used by both userspace applications.

| File | Purpose |
| :-- | :-- |
| `reg_io.h`, `reg_io.c` | `/dev/mem` mapping + register read/write helpers. Includes the fixed AXI address map. |
| `udp.h`, `udp.c`       | Minimal UDP sender used by both applications. |
| `args.h`, `args.c`     | Shared `-n`/`-t`/`-v` CLI parsing. |
| `i2c_dac.h`, `i2c_dac.c` | DAC5578 threshold setup over PS I2C1 (`/dev/i2c-1`). |

The two application Makefiles compile these files directly. There is no
shared library in the source tree — PetaLinux packages them once via the
`yeet-data-common` recipe and both apps link against the resulting
`libscam_common.a`.

## Adding a helper

Add the `.h`/`.c` pair here, then update both `sw/tdc/Makefile` and
`sw/ct/Makefile` to include the new file. The BitBake recipe
`yeet-data-common.bb` will pick up the source automatically (SRC_URI
lists each file explicitly — update that too).
