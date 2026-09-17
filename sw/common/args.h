/* args.h -- shared CLI parsing. */
#ifndef SCAM_ARGS_H
#define SCAM_ARGS_H

#include <stdint.h>

typedef struct {
    const char *dest_ip;
    long        max_hits;    /* -1 = unlimited */
    long        max_seconds; /* -1 = unlimited */
    int         dac_mv;      /* -1 = do not touch DAC */
} app_args_t;

void args_parse(int argc, char **argv, app_args_t *out);
void args_usage(const char *progname);

#endif
