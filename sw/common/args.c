#include "args.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void args_usage(const char *progname)
{
    printf("Usage: %s [-n exact_hits] [-t seconds] [-v millivolts] <IP_ADDRESS>\n",
           progname);
    printf("  -n N    stop after N hits (rounded up to nearest packet)\n");
    printf("  -t S    stop after S seconds\n");
    printf("  -v MV   set I2C DAC threshold to MV millivolts before starting\n");
}

void args_parse(int argc, char **argv, app_args_t *out)
{
    out->dest_ip     = NULL;
    out->max_hits    = -1;
    out->max_seconds = -1;
    out->dac_mv      = -1;

    int opt;
    while ((opt = getopt(argc, argv, "n:t:v:")) != -1) {
        switch (opt) {
            case 'n': out->max_hits    = atol(optarg); break;
            case 't': out->max_seconds = atol(optarg); break;
            case 'v': out->dac_mv      = atoi(optarg); break;
            default:  args_usage(argv[0]); exit(1);
        }
    }
    if (optind >= argc) {
        fprintf(stderr, "ERROR: missing destination IP address\n");
        args_usage(argv[0]);
        exit(1);
    }
    out->dest_ip = argv[optind];
}
