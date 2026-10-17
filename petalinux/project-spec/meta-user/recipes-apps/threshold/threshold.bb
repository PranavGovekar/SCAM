SUMMARY = "SCAM DAC threshold setter"
LICENSE = "CLOSED"

DEPENDS = "yeet-data-common"

SRC_URI = "file://threshold.c \
           file://Makefile \
          "

S = "${WORKDIR}"

EXTRA_OEMAKE = "CC='${CC}' CFLAGS='${CFLAGS} -I${STAGING_INCDIR}' LDFLAGS='${LDFLAGS} -L${STAGING_LIBDIR}' LDLIBS='-lscam_common'"

do_compile() {
    oe_runmake
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 threshold ${D}${bindir}/
}
