/* i2c_dac.h -- DAC5578 threshold setup over I2C1. */
#ifndef SCAM_I2C_DAC_H
#define SCAM_I2C_DAC_H

#define I2C_DAC_CHANNELS  8
#define I2C_DAC_ALL       (-1)   /* channel argument: every channel */

/* Set one DAC channel (0..7), or all with I2C_DAC_ALL. Returns 0 or -1, once
 * the threshold at the comparators has settled.
 * DAC channel to card channel: A(0)=0, B(1)=1, C(2)=2, H(7)=3, E(4)=4; F(5) is
 * card channel 4's second comparator (clock output), D(3) and G(6) are
 * unconnected (FMC DIO schematic EDA-02408, sheet 5). */
int i2c_dac_set_channel(int channel, int millivolts);

/* Set all channels to the same threshold. */
int i2c_dac_set_threshold(int millivolts);

#endif
