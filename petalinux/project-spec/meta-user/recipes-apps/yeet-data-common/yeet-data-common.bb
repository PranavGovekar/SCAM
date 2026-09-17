SUMMARY = "SCAM shared userspace helpers"
LICENSE = "CLOSED"

SRC_URI = "file://reg_io.h \
           file://reg_io.c \
           file://udp.h \
           file://udp.c \
           file://args.h \
           file://args.c \
           file://i2c_dac.h \
           file://i2c_dac.c \
          "

S = "$" + "{WORKDIR}"

# Static library + headers
do_compile() {
    $"{CC}" $"{CFLAGS}" -c reg_io.c udp.c args.c i2c_dac.c
    $"{AR}" rcs libscam_common.a reg_io.o udp.o args.o i2c_dac.o
}

do_install() {
    install -d $"{D}$"{includedir}
    install -m 0644 reg_io.h  $"{D}$"{includedir}/
    install -m 0644 udp.h     $"{D}$"{includedir}/
    install -m 0644 args.h    $"{D}$"{includedir}/
    install -m 0644 i2c_dac.h $"{D}$"{includedir}/

    install -d $"{D}$"{libdir}
    install -m 0644 libscam_common.a $"{D}$"{libdir}/
}
