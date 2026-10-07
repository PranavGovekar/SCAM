# PetaLinux Project

Standard PetaLinux project layout. The generated files (`build/`,
`images/`, etc.) are gitignored.

## First-time setup

    make base-xsa          # produces hw/base/system.xsa
    make petalinux-config  # imports the XSA, produces config fragments
    make petalinux
    make sdcard            # BOOT.BIN, SD image, ./out/

Images are written to `images/linux/`.

## Adding an application

Applications normally do not need a PetaLinux build at all. To bake one into
the image, see `../docs/adding-an-app.md`.

## Do not commit

- `build/`
- `images/`
- `.petalinux/`
- `components/`
