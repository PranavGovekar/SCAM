# Base design constraints.
# The base contains only PS and AXI peripherals; no user I/O pins are
# assigned here. Application projects add their own XDC.

# PL clock at 100 MHz (from PS)
create_clock -period 10.000 -name pl_clk0 [get_ports pl_clk0]

# Fast clock at 400 MHz (from clk_wiz_0)
create_clock -period 2.500 -name clk_fast_400 [get_pins clk_wiz_0/inst/mmcm_adv_inst/CLKOUT0]

# Fast clock at 200 MHz (from clk_wiz_0)
create_clock -period 5.000 -name clk_fast_200 [get_pins clk_wiz_0/inst/mmcm_adv_inst/CLKOUT1]

# Async clock groups
set_clock_groups -asynchronous \
    -group [get_clocks pl_clk0] \
    -group [get_clocks clk_fast_400] \
    -group [get_clocks clk_fast_200]
