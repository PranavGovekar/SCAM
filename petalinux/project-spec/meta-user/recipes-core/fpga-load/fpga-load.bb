SUMMARY = "SCAM FPGA bitstream auto-load service"
LICENSE = "CLOSED"

SRC_URI = "file://fpga-load.service \
           file://fpga-application.conf \
           file://scam-load \
          "

S = "${WORKDIR}"

inherit systemd

# scam-load does the loading. fpgautil (fpga-manager-script) is installed for
# its other functions, such as 'fpgautil -R'.
RDEPENDS:${PN} = "fpga-manager-script fpga-bitstreams"

SYSTEMD_SERVICE:${PN} = "fpga-load.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 fpga-load.service ${D}${systemd_system_unitdir}/

    install -d ${D}${sysconfdir}
    install -m 0644 fpga-application.conf ${D}${sysconfdir}/

    install -d ${D}${bindir}
    install -m 0755 scam-load ${D}${bindir}/
}

FILES:${PN} = "${systemd_system_unitdir}/fpga-load.service \
                 ${sysconfdir}/fpga-application.conf \
                 ${bindir}/scam-load \
                "
