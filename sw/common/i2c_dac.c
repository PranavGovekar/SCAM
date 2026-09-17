#include "i2c_dac.h"

#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/i2c-dev.h>

#define I2C_BUS_PATH    "/dev/i2c-1"
#define I2C_MUX_ADDR    0x75
#define FMC_HPC0_PORT   0x01
#define DAC5578_ADDR    0x48
#define DAC_VREF_MV     3300

int i2c_dac_set_threshold(int millivolts)
{
    if (millivolts < 0)     millivolts = 0;
    if (millivolts > 3300)  millivolts = 3300;

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

    if (ioctl(fd, I2C_SLAVE, DAC5578_ADDR) < 0) {
        perror("ioctl I2C_SLAVE dac");
        close(fd);
        return -1;
    }

    uint8_t code = (uint8_t)(((uint32_t)millivolts * 255U) / DAC_VREF_MV);

    for (int ch = 0; ch < 8; ch++) {
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
    printf("DAC threshold set to %d mV (code 0x%02X)\n", millivolts, code);
    return 0;
}
