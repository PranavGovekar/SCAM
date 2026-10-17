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
    printf("  -v MV   set I2C DAC threshold to MV millivolts (0..3300) before starting\n");
    printf("With no limit the program runs until interrupted (Ctrl+C).\n");
}

static void usage_cal(const char *progname)
{
    printf("Usage: %s [-n hits] [-t seconds] [-v millivolts] [-c seconds [-C seconds]] <IP_ADDRESS>\n",
           progname);
    printf("  -n N    stop after N hits (rounded up to nearest packet); -1 = no limit\n");
    printf("  -t S    stop after S seconds; -1 = no limit\n");
    printf("  -v MV   set I2C DAC threshold to MV millivolts (0..3300) before starting\n");
    printf("  -c S    calibrate for S seconds at the start, from the calibration input\n");
    printf("          (default: no calibration)\n");
    printf("  -C S    calibrate again every S seconds (needs -c)\n");
    printf("With no limit the program runs until interrupted (Ctrl+C).\n");
}

/* Parse a time in seconds: a positive number, fractions allowed. Exits on anything else. */
static double parse_seconds(const char *progname, char opt, const char *text)
{
    char *end;
    double v = strtod(text, &end);
    if (end == text || *end != '\0' || !(v > 0)) {
        fprintf(stderr, "ERROR: -%c needs a positive number of seconds (got '%s')\n", opt, text);
        usage_cal(progname);
        exit(1);
    }
    return v;
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

/* Parse the DAC threshold in millivolts. Exits on anything but a number. */
static int parse_millivolts(const char *progname, const char *text)
{
    char *end;
    long v = strtol(text, &end, 10);
    if (end == text || *end != '\0' || v < 0 || v > 3300) {
        fprintf(stderr, "ERROR: -v needs a threshold from 0 to 3300 millivolts (got '%s')\n", text);
        args_usage(progname);
        exit(1);
    }
    return (int)v;
}

static void parse(int argc, char **argv, app_args_t *out, int calibration)
{
    out->dest_ip      = NULL;
    out->max_hits     = -1;
    out->max_seconds  = -1;
    out->dac_mv       = -1;
    out->cal_window_s = -1;
    out->cal_every_s  = -1;

    int opt;
    while ((opt = getopt(argc, argv, calibration ? "n:t:v:c:C:" : "n:t:v:")) != -1) {
        switch (opt) {
            case 'n': out->max_hits     = parse_limit(argv[0], 'n', optarg); break;
            case 't': out->max_seconds  = parse_limit(argv[0], 't', optarg); break;
            case 'v': out->dac_mv       = parse_millivolts(argv[0], optarg); break;
            case 'c': out->cal_window_s = parse_seconds(argv[0], 'c', optarg); break;
            case 'C': out->cal_every_s  = parse_seconds(argv[0], 'C', optarg); break;
            default:
                if (calibration) usage_cal(argv[0]); else args_usage(argv[0]);
                exit(1);
        }
    }
    if (out->cal_every_s > 0 && out->cal_window_s < 0) {
        fprintf(stderr, "ERROR: -C needs -c (the calibration window)\n");
        usage_cal(argv[0]);
        exit(1);
    }
    if (out->cal_every_s > 0 && out->cal_every_s <= out->cal_window_s) {
        fprintf(stderr, "ERROR: -C must be longer than the calibration window -c\n");
        usage_cal(argv[0]);
        exit(1);
    }
    if (optind >= argc) {
        fprintf(stderr, "ERROR: missing destination IP address\n");
        if (calibration) usage_cal(argv[0]); else args_usage(argv[0]);
        exit(1);
    }
    out->dest_ip = argv[optind];
}

void args_parse(int argc, char **argv, app_args_t *out)
{
    parse(argc, argv, out, 0);
}

void args_parse_cal(int argc, char **argv, app_args_t *out)
{
    parse(argc, argv, out, 1);
}
