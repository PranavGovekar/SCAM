# @APP@

A SCAM application: a bitstream layered on the base design plus a userspace
program. See `docs/adding-an-app.md` in the SCAM repository.

    make @APP@-bitstream                      # build/apps/@APP@/@APP@.bit.bin
    make app-@APP@ SCAM_SDK=<sdk dir>         # build/apps/@APP@/yeet-data-@APP@
    make deploy APP=@APP@ TARGET=petalinux@<board-ip>

## Register use

Document here how this application uses the fixed registers
(`docs/pl-contract.md`).

| Address | Used for |
| :-- | :-- |
| `0xA0010000` | Control GPIO: bit0=enable, bit1=reset |
| `0xA0020000` | Status: constant `0x5CA40001` |
