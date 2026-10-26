/* threshold.c
 *
 * Sets the discriminator thresholds on the FMC card: the DAC5578 on FMC HPC0,
 * reached over PS I2C1 (see sw/common/i2c_dac.c). Independent of the loaded
 * bitstream; the value stays until it is set again or the board loses power.
 *
 *   threshold 1000        all 8 channels to 1000 mV
 *   threshold -c 2 850    DAC channel 2 only (card channel 2)
 *
 * DAC channels are not card channels: card channel 3 is DAC channel 7 (see
 * i2c_dac.h).
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "i2c_dac.h"

static void usage(const char *progname)
{
    printf("Usage: %s [-c channel] <millivolts>\n", progname);
    printf("  -c CH   set only DAC channel CH (0..%d); default is all channels\n",
           I2C_DAC_CHANNELS - 1);
    printf("          card channel 0, 1, 2, 3, 4 = DAC channel 0, 1, 2, 7, 4\n");
    printf("  millivolts: 0..3300\n");
}

/* Parse a whole number in [lo, hi]. Exits on anything else. */
static long parse_number(const char *progname, const char *what, const char *text,
                         long lo, long hi)
{
    char *end;
    long v = strtol(text, &end, 10);
    if (end == text || *end != '\0' || v < lo || v > hi) {
        fprintf(stderr, "ERROR: %s must be %ld..%ld (got '%s')\n", what, lo, hi, text);
        usage(progname);
        exit(1);
    }
    return v;
}

int main(int argc, char **argv)
{
    int channel = I2C_DAC_ALL;

    int opt;
    while ((opt = getopt(argc, argv, "c:h")) != -1) {
        switch (opt) {
            case 'c': channel = (int)parse_number(argv[0], "channel", optarg,
                                                  0, I2C_DAC_CHANNELS - 1); break;
            case 'h': usage(argv[0]); return 0;
            default:  usage(argv[0]); return 1;
        }
    }
    if (optind != argc - 1) {
        usage(argv[0]);
        return 1;
    }
    int millivolts = (int)parse_number(argv[0], "millivolts", argv[optind], 0, 3300);

    if (i2c_dac_set_channel(channel, millivolts) != 0) {
        fprintf(stderr, "ERROR: DAC not set (run as root?)\n");
        return 1;
    }
    return 0;
}
