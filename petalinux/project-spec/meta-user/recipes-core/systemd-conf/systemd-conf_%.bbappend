# DNS servers for systemd-resolved. scripts/build_petalinux.sh writes
# scam-dns.conf from SCAM_DNS in config.mk before every build.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://scam-dns.conf"

do_install:append() {
    install -d ${D}${sysconfdir}/systemd/resolved.conf.d
    install -m 0644 ${WORKDIR}/scam-dns.conf ${D}${sysconfdir}/systemd/resolved.conf.d/
}

FILES:${PN} += "${sysconfdir}/systemd/resolved.conf.d/scam-dns.conf"
