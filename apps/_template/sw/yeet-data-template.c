/*
 * yeet-data-@APP@ -- starting point for a SCAM userspace application.
 *
 * Resets and enables the PL logic through the control GPIO, then prints the
 * status register. The helpers in sw/common/ (reg_io, udp, args, i2c_dac) are
 * compiled in automatically; see apps/tdc/sw and apps/ct/sw for full readout
 * loops that stream data over UDP.
 */
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

#include "reg_io.h"

int main(void)
{
    void *ctrl   = map_phys(AXI_GPIO_CTRL, REG_SIZE);
    void *status = map_phys(AXI_GPIO_STATUS, REG_SIZE);

    if (ctrl == MAP_FAILED || status == MAP_FAILED) {
        fprintf(stderr, "cannot map PL registers (run as root)\n");
        return 1;
    }

    /* Reset, release, enable: the sequence every SCAM application uses. */
    write_reg(ctrl, GPIO_DATA, CTRL_RESET);
    usleep(1000);
    write_reg(ctrl, GPIO_DATA, CTRL_CLEAR);
    usleep(1000);
    write_reg(ctrl, GPIO_DATA, CTRL_WAKEUP);

    printf("status = 0x%08x\n", read_reg(status, GPIO_DATA));
    return 0;
}
