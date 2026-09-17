SUMMARY = "SCAM FPGA bitstream auto-load service"
LICENSE = "CLOSED"

SRC_URI = "file://fpga-load.service \
           file://fpga-application.conf \
          "

S = "$" + "{WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:$" + "{PN} = "fpga-load.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d $"{D}$"{systemd_system_unitdir}
    install -m 0644 fpga-load.service $"{D}$"{systemd_system_unitdir}/

    install -d $"{D}$"{sysconfdir}
    install -m 0644 fpga-application.conf $"{D}$"{sysconfdir}/
}

FILES:$" + "{PN} = "$"{systemd_system_unitdir}/fpga-load.service \
                 $" + "{sysconfdir}/fpga-application.conf \
                "
