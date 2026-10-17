/* yeet-data-tdc.c
 *
 * TDC readout + UDP streamer.
 *
 * Reads 1440-byte packets (90 hits x 16 bytes) from the AXI DMA S2MM
 * path and streams them over UDP to a host PC.
 *
 * Control sequence:
 *   1. assert reset on gpio_ctrl bit 1 (active-low reset via PS reset IP)
 *   2. release reset
 *   3. assert enable on gpio_ctrl bit 0
 *
 * Optionally configures an external I2C DAC threshold on startup (-v flag).
 *
 * Calibration (-c window, -C repeat): the firmware switches the calibration
 * input onto both channels; its records arrive through the DMA, tagged with
 * channel ID 0x800 + channel, and are histogrammed here, one histogram per
 * delay line. After the window the code-density tables are sent as
 * calibration words (see "Calibration words" below), then physics continues.
 * Physics words are forwarded unchanged, 90 to a packet.
 */

#include <sys/mman.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>

#include "reg_io.h"
#include "udp.h"
#include "args.h"
#include "i2c_dac.h"

#define HIT_SIZE_BYTES     16
#define HITS_PER_PACKET    90
#define PACKET_SIZE_BYTES  (HIT_SIZE_BYTES * HITS_PER_PACKET)
#define UDP_PORT           8080

#define POLL_SLEEP_US      10
#define WATCHDOG_TICKS     200000

/* Calibration. A delay line is ch * 2 + 0 (start, rising edge) or + 1 (stop). */
#define NUM_LINES          4
#define NUM_CODES          1024      /* fine codes are 10 bits */
#define CLOCK_PERIOD_PS    2500.0
#define LAST_TAP           784       /* code when the edge ran the whole line */
#define CAL_SWITCH_TIMEOUT_US 100000

#define CONFIG_CAL_REQUEST 0x1       /* axi_gpio_config ch1 bit 0 */
#define FLAGS_CAL_ACTIVE   0x1       /* axi_gpio_flags bit 0 */

/* Channel-ID field (bits 127:116) of a DMA word: 0x800 + ch is a
 * calibration record, anything without bit 11 a physics hit. */
#define ID_CAL_RECORD      0x800

/* Calibration words, sent in ordinary 90-word packets. Bits 127:120: */
#define WORD_CAL_HEADER    0xC1
#define WORD_CAL_TABLE     0xC2
#define WORD_PADDING       0xCF
#define TABLE_PER_WORD     6         /* u16 entries per table word */
#define TABLE_UNIT_PER_PS  16.0      /* entries are in 1/16 ps */

/* Quality flags in the header word. */
#define CAL_FLAG_FEW_HITS  0x001     /* fewer than MIN_HITS_PER_CODE */
#define CAL_FLAG_EMPTY     0x002     /* more than MAX_EMPTY_FRACTION empty codes */
#define CAL_FLAG_WIDE      0x004     /* a bin wider than WIDE_FACTOR x mean */
#define CAL_FLAG_RANGE     0x008     /* fewer than MIN_CODES codes, or the last tap */
#define CAL_FLAG_DROPPED   0x010     /* calibration FIFO was full (information) */

#define MIN_HITS_PER_CODE  50
#define MAX_EMPTY_FRACTION 0.10
#define WIDE_FACTOR        16.0
#define MIN_CODES          400

static volatile sig_atomic_t keep_running = 1;

static uint32_t histogram[NUM_LINES][NUM_CODES];

static void on_sigint(int sig)
{
    (void)sig;
    keep_running = 0;
}

/* Put the TDC logic in reset, restart the DMA, release the reset. The TDC is
 * left disabled. Resetting both together keeps the TDC's count of hits per
 * packet in step with the DMA transfer. */
static void reset_tdc_and_dma(void *gpio_ctrl, void *dma_ctrl)
{
    write_reg(gpio_ctrl, GPIO_DATA, CTRL_RESET);
    usleep(100);

    write_reg(dma_ctrl, S2MM_CR, S2MM_CR_RESET);
    while (read_reg(dma_ctrl, S2MM_CR) & S2MM_CR_RESET) usleep(100);
    write_reg(dma_ctrl, S2MM_CR, S2MM_CR_RS);

    write_reg(gpio_ctrl, GPIO_DATA, CTRL_CLEAR);
    usleep(10);
}

static double now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void put_word(uint8_t *dst, uint64_t lo, uint64_t hi)
{
    memcpy(dst, &lo, 8);         /* little-endian, like the DMA words */
    memcpy(dst + 8, &hi, 8);
}

/* Request calibration mode on or off and wait until the firmware has
 * switched. Returns 0, or -1 if it never did (bitstream without calibration). */
static int set_cal_mode(void *gpio_config, void *gpio_flags, int on)
{
    write_reg(gpio_config, GPIO_DATA, on ? CONFIG_CAL_REQUEST : 0);
    for (int waited = 0; waited < CAL_SWITCH_TIMEOUT_US; waited += 10) {
        if (((read_reg(gpio_flags, GPIO_DATA) & FLAGS_CAL_ACTIVE) != 0) == on) return 0;
        usleep(10);
    }
    return -1;
}

/* Packets of calibration words being assembled. */
typedef struct {
    udp_socket_t *sock;
    uint8_t buf[PACKET_SIZE_BYTES];
    int words;
    long packets;
    int failed;
} cal_out_t;

static void cal_out_word(cal_out_t *o, uint64_t lo, uint64_t hi)
{
    put_word(o->buf + o->words * HIT_SIZE_BYTES, lo, hi);
    if (++o->words == HITS_PER_PACKET) {
        if (udp_send(o->sock, o->buf, PACKET_SIZE_BYTES) < 0) o->failed = 1;
        o->packets++;
        o->words = 0;
    }
}

static void cal_out_flush(cal_out_t *o)
{
    if (o->words == 0) return;
    while (o->words != 0) cal_out_word(o, 0, (uint64_t)WORD_PADDING << 56);
}

/* Build the code-density table of one line from its histogram and send it:
 * one header word, then the bin-centre time of each code from code_lo to
 * code_hi, TABLE_PER_WORD to a word. Same arithmetic as code_density() in
 * sw/host/test_tdc.py. Prints a one-line summary. */
static void send_line(cal_out_t *o, int cal_id, int line, uint32_t dropped, double window_s)
{
    const uint32_t *n = histogram[line];
    uint64_t total = 0;
    int lo = -1, hi = -1;
    for (int k = 0; k < NUM_CODES; k++) {
        if (n[k] == 0) continue;
        total += n[k];
        if (lo < 0) lo = k;
        hi = k;
    }

    int span = 0, empty = 0, wide = 0;
    unsigned flags = dropped ? CAL_FLAG_DROPPED : 0;
    if (total == 0) {
        lo = hi = 0;
        flags |= CAL_FLAG_FEW_HITS | CAL_FLAG_RANGE;
    } else {
        span = hi - lo + 1;
        double wide_limit = WIDE_FACTOR * (double)total / span;
        for (int k = lo; k <= hi; k++) {
            if (n[k] == 0) empty++;
            if (n[k] > wide_limit) wide++;
        }
        if ((double)total / span < MIN_HITS_PER_CODE) flags |= CAL_FLAG_FEW_HITS;
        if (empty > MAX_EMPTY_FRACTION * span)        flags |= CAL_FLAG_EMPTY;
        if (wide > 0)                                 flags |= CAL_FLAG_WIDE;
        if (span < MIN_CODES || hi >= LAST_TAP)       flags |= CAL_FLAG_RANGE;
    }

    int table_words = (span + TABLE_PER_WORD - 1) / TABLE_PER_WORD;
    long window_ms = (long)(window_s * 1000.0 + 0.5);
    if (window_ms > 0xFFFF) window_ms = 0xFFFF;
    uint64_t hits = total > 0xFFFFFFFFu ? 0xFFFFFFFFu : total;

    uint64_t tag = ((uint64_t)(cal_id & 0xFF) << 48) | ((uint64_t)line << 44);
    cal_out_word(o,
        ((uint64_t)lo << 54) | ((uint64_t)hi << 44) | ((uint64_t)empty << 34) |
        ((uint64_t)wide << 24) | ((uint64_t)table_words << 16) | (uint64_t)window_ms,
        ((uint64_t)WORD_CAL_HEADER << 56) | tag | ((uint64_t)flags << 32) | hits);

    double cum = 0;
    for (int w = 0; w < table_words; w++) {
        int first = lo + w * TABLE_PER_WORD;
        uint64_t e[TABLE_PER_WORD] = {0};
        for (int j = 0; j < TABLE_PER_WORD && first + j <= hi; j++) {
            double t_ps = CLOCK_PERIOD_PS * (cum + n[first + j] / 2.0) / (double)total;
            e[j] = (uint64_t)(t_ps * TABLE_UNIT_PER_PS + 0.5);
            cum += n[first + j];
        }
        cal_out_word(o,
            e[0] | (e[1] << 16) | (e[2] << 32) | (e[3] << 48),
            ((uint64_t)WORD_CAL_TABLE << 56) | tag | ((uint64_t)first << 34) |
            e[4] | (e[5] << 16));
    }

    printf("[cal %d] ch%d %-5s: %llu hits, codes %d..%d, %d empty, %d wide, flags 0x%03X\n",
           cal_id, line / 2, (line & 1) ? "stop" : "start",
           (unsigned long long)total, lo, hi, empty, wide, flags);
}

int main(int argc, char **argv)
{
    app_args_t args;
    args_parse_cal(argc, argv, &args);

    /* Any ordinary way of stopping the program ends the run cleanly, including
       the SSH session that started it going away. */
    signal(SIGINT, on_sigint);
    signal(SIGTERM, on_sigint);
    signal(SIGHUP, on_sigint);

    if (args.dac_mv >= 0) {
        if (i2c_dac_set_threshold(args.dac_mv) != 0) {
            fprintf(stderr, "WARN: DAC setup failed, continuing without\n");
        }
    } else {
        printf("Note: threshold not set (the card powers up at 0 V). "
               "Use -v <mV> or 'sudo threshold <mV>'.\n");
    }

    void *dma_ctrl  = map_phys(AXI_DMA_BASE,    REG_SIZE);
    void *gpio_ctrl = map_phys(AXI_GPIO_CTRL,   REG_SIZE);
    void *gpio_mon  = map_phys(AXI_GPIO_STATUS, REG_SIZE);
    void *gpio_config  = map_phys(AXI_GPIO_CONFIG,  REG_SIZE);
    void *gpio_caldrop = map_phys(AXI_GPIO_STATUS2, REG_SIZE);
    void *gpio_flags   = map_phys(AXI_GPIO_FLAGS,   REG_SIZE);
    if (dma_ctrl == MAP_FAILED || gpio_ctrl == MAP_FAILED || gpio_mon == MAP_FAILED ||
        gpio_config == MAP_FAILED || gpio_caldrop == MAP_FAILED || gpio_flags == MAP_FAILED) {
        return 1;
    }

    uint8_t *dma_ram = map_phys(DMA_RAM_BASE, DMA_RAM_SIZE);
    if (dma_ram == MAP_FAILED) return 1;

    udp_socket_t sock;
    if (udp_open(&sock, args.dest_ip, UDP_PORT) != 0) return 1;

    printf("=== TDC STREAM ===\n");
    printf("Target : %s:%u\n", args.dest_ip, UDP_PORT);
    if (args.cal_window_s > 0) {
        printf("Calibration: %.3g s window, %s\n", args.cal_window_s,
               args.cal_every_s > 0 ? "repeated" : "once at the start");
        if (args.cal_every_s > 0) printf("             every %.3g s\n", args.cal_every_s);
    }

    write_reg(gpio_ctrl, GPIO_TRI, 0x00000000);
    write_reg(gpio_config, GPIO_TRI, 0x00000000);
    /* The config register keeps its value between runs: start in physics mode. */
    write_reg(gpio_config, GPIO_DATA, 0);

    reset_tdc_and_dma(gpio_ctrl, dma_ctrl);

    long hits_sent    = 0;
    long packets_sent = 0;
    time_t start_time = time(NULL);
    uint32_t ram_offset = 0;

    /* The packet just received, and physics words waiting to be sent. */
    static uint8_t pkt[PACKET_SIZE_BYTES] __attribute__((aligned(64)));
    static uint8_t out[PACKET_SIZE_BYTES];
    int out_words = 0;
    int send_failed = 0;

    /* Calibration state. */
    int    cal_running   = 0;
    int    cal_count     = 0;
    double cal_next      = args.cal_window_s > 0 ? now_s() : -1;  /* -1 = none due */
    double cal_started   = 0;
    uint32_t cal_drop0   = 0;
    long   cal_packets   = 0;
    long   cal_stray     = 0;

    while (keep_running && !send_failed) {
        if (args.max_seconds > 0 && (time(NULL) - start_time) >= args.max_seconds) break;
        if (args.max_hits    > 0 && hits_sent >= args.max_hits) break;

        /* The channel is ready for a new transfer here: it was just started,
         * or the previous transfer completed. Do not wait for the Idle status
         * bit, which in direct-register mode is only set once a transfer has
         * completed and so never before the first one. */
        write_reg(dma_ctrl, S2MM_DA, DMA_RAM_BASE + ram_offset);
        write_reg(dma_ctrl, S2MM_LENGTH, PACKET_SIZE_BYTES);

        write_reg(gpio_ctrl, GPIO_DATA, CTRL_WAKEUP);

        int watchdog = 0;
        int dma_error = 0;
        int timed_out = 0;
        for (;;) {
            /* Start or end a calibration window. Checked here, while waiting
             * for data, so a missing calibration signal cannot stall it. */
            if (!cal_running && cal_next >= 0 && now_s() >= cal_next) {
                cal_drop0 = read_reg(gpio_caldrop, GPIO_DATA);
                memset(histogram, 0, sizeof(histogram));
                if (set_cal_mode(gpio_config, gpio_flags, 1) != 0) {
                    fprintf(stderr, "[WARN] the firmware did not enter calibration mode; "
                                    "is this a TDC bitstream with calibration? "
                                    "Calibration disabled.\n");
                    set_cal_mode(gpio_config, gpio_flags, 0);
                    cal_next = -1;
                } else {
                    cal_running = 1;
                    cal_started = now_s();
                }
            }
            if (cal_running && now_s() - cal_started >= args.cal_window_s) {
                double window = now_s() - cal_started;
                if (set_cal_mode(gpio_config, gpio_flags, 0) != 0)
                    fprintf(stderr, "[WARN] the firmware did not leave calibration mode\n");
                cal_running = 0;
                uint32_t dropped = read_reg(gpio_caldrop, GPIO_DATA) - cal_drop0;
                cal_out_t co = { .sock = &sock };
                for (int line = 0; line < NUM_LINES; line++)
                    send_line(&co, cal_count, line, dropped, window);
                cal_out_flush(&co);
                if (dropped) printf("[cal %d] %u calibration hits dropped (FIFO full)\n",
                                    cal_count, dropped);
                fflush(stdout);
                cal_packets  += co.packets;
                packets_sent += co.packets;
                if (co.failed) send_failed = 1;
                cal_count++;
                cal_next = args.cal_every_s > 0 ? cal_started + args.cal_every_s : -1;
            }

            if (read_reg(dma_ctrl, S2MM_SR) & S2MM_SR_IOC) break;
            if (!keep_running) break;
            /* A packet only completes after 90 hits, so the time limit has to
             * be checked while waiting as well. */
            if (args.max_seconds > 0 && (time(NULL) - start_time) >= args.max_seconds) {
                timed_out = 1;
                break;
            }
            usleep(POLL_SLEEP_US);
            if (++watchdog >= WATCHDOG_TICKS) {
                uint32_t sr = read_reg(dma_ctrl, S2MM_SR);
                if (sr & S2MM_SR_ERR_MASK) {
                    fprintf(stderr, "[WARN] DMA error SR=0x%08X, resetting\n", sr);
                    reset_tdc_and_dma(gpio_ctrl, dma_ctrl);
                    dma_error = 1;
                    break;
                }
                watchdog = 0;
            }
        }
        if (!keep_running || timed_out || send_failed) break;
        if (dma_error) continue;

        write_reg(dma_ctrl, S2MM_SR, S2MM_SR_IOC);
        __sync_synchronize();

        /* Physics words go out unchanged; calibration records feed the
         * histograms while a window is open and are dropped otherwise. The
         * DMA buffer is uncached: read it once. */
        memcpy(pkt, dma_ram + ram_offset, PACKET_SIZE_BYTES);
        const uint8_t *in = pkt;
        for (int i = 0; i < HITS_PER_PACKET; i++, in += HIT_SIZE_BYTES) {
            uint64_t lo, hi;
            memcpy(&lo, in, 8);
            memcpy(&hi, in + 8, 8);
            unsigned id = (unsigned)(hi >> 52);
            if (!(id & ID_CAL_RECORD)) {
                memcpy(out + out_words * HIT_SIZE_BYTES, in, HIT_SIZE_BYTES);
                if (++out_words == HITS_PER_PACKET) {
                    if (udp_send(&sock, out, PACKET_SIZE_BYTES) < 0) { send_failed = 1; break; }
                    out_words = 0;
                    packets_sent++;
                    hits_sent += HITS_PER_PACKET;
                }
            } else if (cal_running && (id & ~ID_CAL_RECORD) < NUM_LINES / 2) {
                int line = (int)(id & ~ID_CAL_RECORD) * 2;
                histogram[line][lo & 0x3FF]++;
                histogram[line + 1][((lo >> 58) | (hi << 6)) & 0x3FF]++;
            } else {
                cal_stray++;
            }
        }

        ram_offset += PACKET_SIZE_BYTES;
        if (ram_offset + PACKET_SIZE_BYTES > DMA_RAM_SIZE) ram_offset = 0;
    }

    /* Disable first so the overflow counter stops changing, read it, and only
       then reset: the reset clears the counter. */
    write_reg(gpio_config, GPIO_DATA, 0);
    write_reg(gpio_ctrl, GPIO_DATA, CTRL_CLEAR);
    usleep(10);
    uint32_t dropped = read_reg(gpio_mon, GPIO_DATA);
    write_reg(gpio_ctrl, GPIO_DATA, CTRL_RESET);

    write_reg(dma_ctrl, S2MM_CR, read_reg(dma_ctrl, S2MM_CR) & ~S2MM_CR_RS);

    printf("\n=== DONE ===\n");
    printf("Hits yeeted   : %ld\n", hits_sent);
    printf("Packets sent  : %ld\n", packets_sent);
    printf("Overflow count: %u\n", dropped);
    if (args.cal_window_s > 0) {
        printf("Calibrations  : %d (%ld packets, included in Packets sent)\n",
               cal_count, cal_packets);
        if (cal_stray) printf("Cal. records outside a window: %ld (discarded)\n", cal_stray);
    }

    udp_close(&sock);
    return 0;
}
