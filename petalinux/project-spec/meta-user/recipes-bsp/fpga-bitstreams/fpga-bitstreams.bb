SUMMARY = "SCAM FPGA bitstreams"
LICENSE = "CLOSED"

SRC_URI = "file://tdc.bit.bin \
           file://ct.bit.bin \
          "

S = "${WORKDIR}"

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware
    install -m 0644 tdc.bit.bin ${D}${nonarch_base_libdir}/firmware/
    install -m 0644 ct.bit.bin  ${D}${nonarch_base_libdir}/firmware/
}

FILES:${PN} = "${nonarch_base_libdir}/firmware/*.bit.bin"
