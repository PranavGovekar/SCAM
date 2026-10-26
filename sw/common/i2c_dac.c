#include "i2c_dac.h"

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/i2c-dev.h>

#define I2C_BUS_PATH    "/dev/i2c-1"
#define I2C_MUX_ADDR    0x75
#define FMC_HPC0_PORT   0x01
/* When the kernel's mux driver is bound to the mux at 0x75, each mux port is
 * its own I2C bus and the mux address itself cannot be opened from userspace.
 * This link names the bus behind port 0 (FMC HPC0). */
#define MUX_CHANNEL_LINK "/sys/bus/i2c/devices/1-0075/channel-0"
#define DAC5578_ADDR    0x48
#define DAC_VREF_MV     3300
/* On the FMC DIO card each DAC output reaches its comparator through 10 kohm
 * and 100 nF (1 ms). A full-scale step settles to one DAC step in about 6 ms;
 * wait 20 ms so no hit is taken at the old threshold. */
#define DAC_SETTLE_US   20000

/* Open the I2C bus that reaches the FMC HPC0 connector. Returns an fd, or -1. */
static int open_hpc0_bus(void)
{
    char link[128];
    ssize_t n = readlink(MUX_CHANNEL_LINK, link, sizeof(link) - 1);
    if (n > 0) {
        /* Kernel mux driver present: the link ends in "i2c-<N>". */
        int bus;
        link[n] = '\0';
        const char *name = strrchr(link, '/');
        name = name ? name + 1 : link;
        if (sscanf(name, "i2c-%d", &bus) == 1) {
            char path[32];
            snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
            int fd = open(path, O_RDWR);
            if (fd < 0) perror(path);
            return fd;
        }
    }

    /* No kernel mux driver: select the port by writing to the mux. */
    int fd = open(I2C_BUS_PATH, O_RDWR);
    if (fd < 0) {
        perror("open " I2C_BUS_PATH);
        return -1;
    }
    if (ioctl(fd, I2C_SLAVE, I2C_MUX_ADDR) < 0) {
        perror("ioctl I2C_SLAVE mux");
        close(fd);
        return -1;
    }
    uint8_t port = FMC_HPC0_PORT;
    if (write(fd, &port, 1) != 1) {
        perror("write I2C mux");
        close(fd);
        return -1;
    }
    usleep(10000);
    return fd;
}

int i2c_dac_set_channel(int channel, int millivolts)
{
    if (channel != I2C_DAC_ALL && (channel < 0 || channel >= I2C_DAC_CHANNELS)) {
        fprintf(stderr, "DAC channel %d does not exist (0..%d)\n",
                channel, I2C_DAC_CHANNELS - 1);
        return -1;
    }
    if (millivolts < 0)     millivolts = 0;
    if (millivolts > 3300)  millivolts = 3300;

    int fd = open_hpc0_bus();
    if (fd < 0) return -1;

    if (ioctl(fd, I2C_SLAVE, DAC5578_ADDR) < 0) {
        perror("ioctl I2C_SLAVE dac");
        close(fd);
        return -1;
    }

    uint8_t code = (uint8_t)(((uint32_t)millivolts * 255U) / DAC_VREF_MV);

    int first = (channel == I2C_DAC_ALL) ? 0 : channel;
    int last  = (channel == I2C_DAC_ALL) ? I2C_DAC_CHANNELS - 1 : channel;

    for (int ch = first; ch <= last; ch++) {
        uint8_t buf[3];
        buf[0] = 0x30 | (uint8_t)ch;
        buf[1] = code;
        buf[2] = 0x00;
        if (write(fd, buf, 3) != 3) {
            perror("write DAC channel");
            close(fd);
            return -1;
        }
        usleep(2000);
    }

    close(fd);
    usleep(DAC_SETTLE_US);
    if (channel == I2C_DAC_ALL)
        printf("DAC threshold set to %d mV (code 0x%02X)\n", millivolts, code);
    else
        printf("DAC channel %d set to %d mV (code 0x%02X)\n", channel, millivolts, code);
    return 0;
}

int i2c_dac_set_threshold(int millivolts)
{
    return i2c_dac_set_channel(I2C_DAC_ALL, millivolts);
}
