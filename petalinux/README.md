# PetaLinux Project

Standard PetaLinux project layout. The generated files (`build/`,
`images/`, etc.) are gitignored.

## First-time setup

    make base-xsa          # produces system.xsa
    make petalinux-config  # imports the XSA, produces config fragments
    make petalinux

## Adding an application

See `../docs/build-guide.md`.

## Do not commit

- `build/`
- `images/`
- `.petalinux/`
- `components/`
