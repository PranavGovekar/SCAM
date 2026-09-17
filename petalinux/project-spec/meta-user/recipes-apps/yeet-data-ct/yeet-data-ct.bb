SUMMARY = "SCAM coincidence trigger readout application"
LICENSE = "CLOSED"

DEPENDS = "yeet-data-common"
RDEPENDS:$" + "{PN} = "yeet-data-common"

SRC_URI = "file://yeet-data-ct.c \
           file://Makefile \
          "

S = "$" + "{WORKDIR}"

EXTRA_OEMAKE = "CC='$"{CC}' CFLAGS='$"{CFLAGS} -I$"{STAGING_INCDIR}' LDFLAGS='-L$"{STAGING_LIBDIR} -lscam_common'"

do_compile() {
    oe_runmake
}

do_install() {
    install -d $"{D}$"{bindir}
    install -m 0755 yeet-data-ct $"{D}$"{bindir}/
}
