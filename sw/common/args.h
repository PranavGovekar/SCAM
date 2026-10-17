/* args.h -- shared CLI parsing. */
#ifndef SCAM_ARGS_H
#define SCAM_ARGS_H

#include <stdint.h>

typedef struct {
    const char *dest_ip;
    long        max_hits;    /* -1 = unlimited */
    long        max_seconds; /* -1 = unlimited */
    int         dac_mv;      /* -1 = do not touch DAC */
    double      cal_window_s; /* -1 = no calibration (args_parse_cal only) */
    double      cal_every_s;  /* -1 = calibrate once, at the start */
} app_args_t;

void args_parse(int argc, char **argv, app_args_t *out);
/* args_parse plus the calibration options -c and -C (TDC). */
void args_parse_cal(int argc, char **argv, app_args_t *out);
void args_usage(const char *progname);

#endif
