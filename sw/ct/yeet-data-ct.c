/* yeet-data-ct.c
 *
 * Coincidence trigger readout + UDP streamer.
 *
 * The ct_top FIFO is 512 x 64-bit. It is not behind the DMA -- it is
 * exposed through three AXI GPIO registers:
 *
 *   AXI_GPIO_STATUS   + 0x00  -> fifo_dout[31:0]
 *   AXI_GPIO_STATUS2  + 0x00  -> fifo_dout[63:32]
 *   AXI_GPIO_FLAGS    + 0x00  -> bit0 = fifo_valid (1 clk pulse, often missed)
 *                                bit1 = fifo_empty
 *
 * Read protocol per event:
 *   1. poll fifo_empty; if 1, no data yet
 *   2. read fifo_dout_l, fifo_dout_h
 *   3. write config with pop bit set, then clear (pulse)
 *   4. wait a few microseconds for the FIFO pointer to advance
 *   5. repeat
 *
 * Config register (64-bit dual channel):
 *   ch1 @ 0xA0030000 -> {delay_C, delay_B, delay_A, window_width}
 *   ch2 @ 0xA0030008 -> {11'b0, pop, sel, pulse_width, delay_D}
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>

#include "reg_io.h"
#include "udp.h"
#include "args.h"
#include "i2c_dac.h"

#define UDP_PORT           8080
#define EVENTS_PER_PACKET  1
#define EVENT_SIZE_BYTES   8    /* 64-bit event word sent as-is */

#define POLL_SLEEP_US      5
#define POP_SETTLE_US      2

/* Default configuration */
#define DEFAULT_WINDOW     6    /* 6 * 5 ns = 30 ns at 200 MHz */
#define DEFAULT_PULSE      4
#define DEFAULT_SEL        14   /* bit 14 = ABCD 4-fold */
#define DEFAULT_DELAY      0

static volatile sig_atomic_t keep_running = 1;

static void on_sigint(int sig)
{
    (void)sig;
    printf("\n[SIGINT] stopping\n");
    keep_running = 0;
}

static uint64_t pack_config(uint32_t ch1, uint32_t ch2)
{
    return ((uint64_t)ch2 << 32) | (uint64_t)ch1;
}

static void unpack_config(uint64_t cfg, uint32_t *ch1, uint32_t *ch2)
{
    *ch1 = (uint32_t)(cfg & 0xFFFFFFFFULL);
    *ch2 = (uint32_t)(cfg >> 32);
}

int main(int argc, char **argv)
{
    app_args_t args;
    args_parse(argc, argv, &args);

    signal(SIGINT, on_sigint);

    if (args.dac_mv >= 0) {
        if (i2c_dac_set_threshold(args.dac_mv) != 0) {
            fprintf(stderr, "WARN: DAC setup failed, continuing without\n");
        }
    }

    void *gpio_ctrl    = map_phys(AXI_GPIO_CTRL,    REG_SIZE);
    void *gpio_status  = map_phys(AXI_GPIO_STATUS,  REG_SIZE);
    void *gpio_config  = map_phys(AXI_GPIO_CONFIG,  REG_SIZE);
    void *gpio_status2 = map_phys(AXI_GPIO_STATUS2, REG_SIZE);
    void *gpio_flags   = map_phys(AXI_GPIO_FLAGS,   REG_SIZE);
    if (gpio_ctrl == MAP_FAILED || gpio_status == MAP_FAILED ||
        gpio_config == MAP_FAILED || gpio_status2 == MAP_FAILED ||
        gpio_flags == MAP_FAILED) {
        return 1;
    }

    udp_socket_t sock;
    if (udp_open(&sock, args.dest_ip, UDP_PORT) != 0) return 1;

    printf("=== CT STREAM ===\n");
    printf("Target : %s:%u\n", args.dest_ip, UDP_PORT);

    /* Configure GPIO directions */
    write_reg(gpio_ctrl,   GPIO_TRI,  0x00000000);
    write_reg(gpio_config, GPIO_TRI,  0x00000000);
    write_reg(gpio_config, GPIO2_TRI, 0x00000000);

    /* Reset and wake */
    write_reg(gpio_ctrl, GPIO_DATA, CTRL_RESET);
    usleep(100);
    write_reg(gpio_ctrl, GPIO_DATA, CTRL_CLEAR);
    usleep(10);

    /* Program config: window, delays, pulse_width, sel, pop=0 */
    uint32_t ch1 = ((uint32_t)DEFAULT_DELAY << 24) |
                   ((uint32_t)DEFAULT_DELAY << 16) |
                   ((uint32_t)DEFAULT_DELAY << 8)  |
                   (uint32_t)DEFAULT_WINDOW;
    uint32_t ch2 = ((uint32_t)DEFAULT_SEL << 8) |
                   (uint32_t)DEFAULT_PULSE;
    /* bits [51:48] = sel, [47:40] = pulse_width, [39:32] = delay_D
       In ch2 layout above: sel at [19:16], pulse at [15:8], delay_D at [7:0].
       That's because ch2 covers config[63:32], and config[51:48] -> ch2[19:16],
       config[47:40] -> ch2[15:8], config[39:32] -> ch2[7:0]. */
    ch2 = ((uint32_t)DEFAULT_SEL   << 16) |
          ((uint32_t)DEFAULT_PULSE << 8)  |
          (uint32_t)DEFAULT_DELAY;

    write_reg(gpio_config, GPIO_DATA,  ch1);
    write_reg(gpio_config, GPIO2_DATA, ch2);

    write_reg(gpio_ctrl, GPIO_DATA, CTRL_WAKEUP);

    long hits_sent    = 0;
    long packets_sent = 0;
    time_t start_time = time(NULL);

    uint8_t packet[EVENT_SIZE_BYTES];

    while (keep_running) {
        if (args.max_seconds > 0 && (time(NULL) - start_time) >= args.max_seconds) break;
        if (args.max_hits    > 0 && hits_sent >= args.max_hits) break;

        uint32_t flags = read_reg(gpio_flags, GPIO_DATA);
        if (flags & 0x2) {
            /* FIFO empty */
            usleep(POLL_SLEEP_US);
            continue;
        }

        uint32_t lo = read_reg(gpio_status,  GPIO_DATA);
        uint32_t hi = read_reg(gpio_status2, GPIO_DATA);
        uint64_t ev = ((uint64_t)hi << 32) | (uint64_t)lo;

        /* Pop: pulse bit 20 of ch2 (config[52] -> ch2[20]) */
        uint32_t ch2_pop = ch2 | (1u << 20);
        write_reg(gpio_config, GPIO2_DATA, ch2_pop);
        usleep(POP_SETTLE_US);
        write_reg(gpio_config, GPIO2_DATA, ch2);

        memcpy(packet, &ev, EVENT_SIZE_BYTES);

        if (udp_send(&sock, packet, EVENT_SIZE_BYTES) < 0) break;

        packets_sent++;
        hits_sent += EVENTS_PER_PACKET;
    }

    write_reg(gpio_ctrl, GPIO_DATA, CTRL_CLEAR);
    usleep(10);
    write_reg(gpio_ctrl, GPIO_DATA, CTRL_RESET);

    printf("\n=== DONE ===\n");
    printf("Events sent : %ld\n", hits_sent);

    udp_close(&sock);
    return 0;
}
