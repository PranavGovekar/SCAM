SUMMARY = "SCAM FPGA bitstreams"
LICENSE = "CLOSED"

SRC_URI = "file://tdc.bit.bin \
           file://coincidence.bit.bin \
          "

S = "$" + "{WORKDIR}"

do_install() {
    install -d $"{D}$"{nonarch_base_libdir}/firmware
    install -m 0644 tdc.bit.bin        $"{D}$"{nonarch_base_libdir}/firmware/
    install -m 0644 coincidence.bit.bin $"{D}$"{nonarch_base_libdir}/firmware/
}

FILES:$" + "{PN} = "$"{nonarch_base_libdir}/firmware/*.bit.bin"
