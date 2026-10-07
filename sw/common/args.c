#include "args.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void args_usage(const char *progname)
{
    printf("Usage: %s [-n hits] [-t seconds] [-v millivolts] <IP_ADDRESS>\n",
           progname);
    printf("  -n N    stop after N hits (rounded up to nearest packet); -1 = no limit\n");
    printf("  -t S    stop after S seconds; -1 = no limit\n");
    printf("  -v MV   set I2C DAC threshold to MV millivolts before starting\n");
    printf("With no limit the program runs until interrupted (Ctrl+C).\n");
}

/* Parse a limit: a positive count, or -1 for "no limit". Exits on anything else. */
static long parse_limit(const char *progname, char opt, const char *text)
{
    char *end;
    long v = strtol(text, &end, 10);
    if (end == text || *end != '\0' || (v <= 0 && v != -1)) {
        fprintf(stderr, "ERROR: -%c needs a positive number, or -1 for no limit (got '%s')\n",
                opt, text);
        args_usage(progname);
        exit(1);
    }
    return v;
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
            case 'n': out->max_hits    = parse_limit(argv[0], 'n', optarg); break;
            case 't': out->max_seconds = parse_limit(argv[0], 't', optarg); break;
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
