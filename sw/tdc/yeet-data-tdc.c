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
 */

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
#define DMA_RAM_BASE       0x70000000UL
#define DMA_RAM_SIZE       0x00100000UL

#define POLL_SLEEP_US      10
#define WATCHDOG_TICKS     200000

static volatile sig_atomic_t keep_running = 1;

static void on_sigint(int sig)
{
    (void)sig;
    printf("\n[SIGINT] stopping\n");
    keep_running = 0;
}

static void dma_reset_and_start(void *dma_ctrl)
{
    write_reg(dma_ctrl, S2MM_CR, S2MM_CR_RESET);
    while (read_reg(dma_ctrl, S2MM_CR) & S2MM_CR_RESET) usleep(100);
    write_reg(dma_ctrl, S2MM_CR, S2MM_CR_RS);
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

    void *dma_ctrl  = map_phys(AXI_DMA_BASE,    REG_SIZE);
    void *gpio_ctrl = map_phys(AXI_GPIO_CTRL,   REG_SIZE);
    void *gpio_mon  = map_phys(AXI_GPIO_STATUS, REG_SIZE);
    if (dma_ctrl == MAP_FAILED || gpio_ctrl == MAP_FAILED || gpio_mon == MAP_FAILED) {
        return 1;
    }

    uint8_t *dma_ram = map_phys(DMA_RAM_BASE, DMA_RAM_SIZE);
    if (dma_ram == MAP_FAILED) return 1;

    udp_socket_t sock;
    if (udp_open(&sock, args.dest_ip, UDP_PORT) != 0) return 1;

    printf("=== TDC STREAM ===\n");
    printf("Target : %s:%u\n", args.dest_ip, UDP_PORT);

    write_reg(gpio_ctrl, GPIO_TRI, 0x00000000);

    write_reg(gpio_ctrl, GPIO_DATA, CTRL_RESET);
    usleep(100);

    dma_reset_and_start(dma_ctrl);

    write_reg(gpio_ctrl, GPIO_DATA, CTRL_CLEAR);
    usleep(10);

    long hits_sent    = 0;
    long packets_sent = 0;
    time_t start_time = time(NULL);
    uint32_t ram_offset = 0;

    while (keep_running) {
        if (args.max_seconds > 0 && (time(NULL) - start_time) >= args.max_seconds) break;
        if (args.max_hits    > 0 && hits_sent >= args.max_hits) break;

        while (!(read_reg(dma_ctrl, S2MM_SR) & S2MM_SR_IDLE)) {
            if (!keep_running) break;
            usleep(POLL_SLEEP_US);
        }
        if (!keep_running) break;

        write_reg(dma_ctrl, S2MM_DA, DMA_RAM_BASE + ram_offset);
        write_reg(dma_ctrl, S2MM_LENGTH, PACKET_SIZE_BYTES);

        write_reg(gpio_ctrl, GPIO_DATA, CTRL_WAKEUP);

        int watchdog = 0;
        int dma_error = 0;
        while (!(read_reg(dma_ctrl, S2MM_SR) & S2MM_SR_IOC)) {
            if (!keep_running) break;
            usleep(POLL_SLEEP_US);
            if (++watchdog >= WATCHDOG_TICKS) {
                uint32_t sr = read_reg(dma_ctrl, S2MM_SR);
                if (sr & S2MM_SR_ERR_MASK) {
                    fprintf(stderr, "[WARN] DMA error SR=0x%08X, resetting\n", sr);
                    dma_reset_and_start(dma_ctrl);
                    dma_error = 1;
                    break;
                }
                watchdog = 0;
            }
        }
        if (!keep_running) break;
        if (dma_error) continue;

        write_reg(dma_ctrl, S2MM_SR, S2MM_SR_IOC);
        __sync_synchronize();

        if (udp_send(&sock, dma_ram + ram_offset, PACKET_SIZE_BYTES) < 0) break;

        packets_sent++;
        hits_sent += HITS_PER_PACKET;
        ram_offset += PACKET_SIZE_BYTES;
        if (ram_offset + PACKET_SIZE_BYTES > DMA_RAM_SIZE) ram_offset = 0;
    }

    write_reg(gpio_ctrl, GPIO_DATA, CTRL_CLEAR);
    usleep(10);
    write_reg(gpio_ctrl, GPIO_DATA, CTRL_RESET);

    uint32_t dropped = read_reg(gpio_mon, GPIO_DATA);

    write_reg(dma_ctrl, S2MM_CR, read_reg(dma_ctrl, S2MM_CR) & ~S2MM_CR_RS);

    printf("\n=== DONE ===\n");
    printf("Hits yeeted   : %ld\n", hits_sent);
    printf("Packets sent  : %ld\n", packets_sent);
    printf("Overflow count: %u\n", dropped);

    udp_close(&sock);
    return 0;
}
