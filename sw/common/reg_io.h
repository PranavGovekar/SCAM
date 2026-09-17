/* reg_io.h -- /dev/mem register helpers and shared address map. */
#ifndef SCAM_REG_IO_H
#define SCAM_REG_IO_H

#include <stdint.h>
#include <stddef.h>

/* Fixed AXI footprint (see docs/pl-contract.md). */
#define AXI_DMA_BASE        0xA0000000UL
#define AXI_GPIO_CTRL       0xA0010000UL
#define AXI_GPIO_STATUS     0xA0020000UL
#define AXI_GPIO_CONFIG     0xA0030000UL
#define AXI_GPIO_STATUS2    0xA0040000UL
#define AXI_GPIO_FLAGS      0xA0050000UL

#define REG_SIZE            0x1000

/* Common register offsets */
#define GPIO_DATA           0x00
#define GPIO_TRI            0x04
#define GPIO2_DATA          0x08
#define GPIO2_TRI           0x0C

/* DMA S2MM register offsets */
#define S2MM_CR             0x30
#define S2MM_SR             0x34
#define S2MM_DA             0x48
#define S2MM_LENGTH         0x58

#define S2MM_CR_RS          0x00000001
#define S2MM_CR_RESET       0x00000004
#define S2MM_CR_IOC_IRQ_EN  0x00001000
#define S2MM_CR_ERR_IRQ_EN  0x00004000

#define S2MM_SR_IDLE        0x00000002
#define S2MM_SR_IOC         0x00001000
#define S2MM_SR_ERR_MASK    0x00000070

/* Control word written to AXI_GPIO_CTRL */
#define CTRL_RESET          0x00  /* bit1=0 (assert reset), bit0=0 */
#define CTRL_CLEAR          0x02  /* bit1=1 (release reset), bit0=0 */
#define CTRL_WAKEUP         0x03  /* bit1=1, bit0=1 (enable) */

/* mmap helper */
void *map_phys(uint32_t base, size_t size);

static inline void write_reg(void *base, uint32_t off, uint32_t val)
{
    *((volatile uint32_t *)((uint8_t *)base + off)) = val;
}

static inline uint32_t read_reg(void *base, uint32_t off)
{
    return *((volatile uint32_t *)((uint8_t *)base + off));
}

#endif
