# =========================================================================
# TDC constraints -- restored from the previously working const_ZCU.xdc
# pinout/timing/placement, adapted to the unified base architecture.
# =========================================================================

# =========================================================================
# 1. I/O CONSTRAINTS
# =========================================================================
set_property PACKAGE_PIN AB4 [get_ports led_0]
set_property IOSTANDARD LVCMOS18 [get_ports led_0]

# LED pattern (runs while the TDC is enabled) on ZCU102 GPIO_LED_0..4.
set_property PACKAGE_PIN AG14 [get_ports {led_pattern[0]}]
set_property PACKAGE_PIN AF13 [get_ports {led_pattern[1]}]
set_property PACKAGE_PIN AE13 [get_ports {led_pattern[2]}]
set_property PACKAGE_PIN AJ14 [get_ports {led_pattern[3]}]
set_property PACKAGE_PIN AJ15 [get_ports {led_pattern[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_pattern[*]}]

# Channel 0: FMC DIO card channel 0 (LA33)
set_property PACKAGE_PIN V12 [get_ports diff_in_p_0]
set_property IOSTANDARD LVDS [get_ports diff_in_p_0]
set_property PACKAGE_PIN V11 [get_ports diff_in_n_0]
set_property IOSTANDARD LVDS [get_ports diff_in_n_0]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_p_0]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_n_0]

# Channel 1: FMC DIO card channel 1 (LA20)
set_property PACKAGE_PIN N13 [get_ports diff_in_p_1]
set_property IOSTANDARD LVDS [get_ports diff_in_p_1]
set_property PACKAGE_PIN M13 [get_ports diff_in_n_1]
set_property IOSTANDARD LVDS [get_ports diff_in_n_1]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_p_1]

# Channel 2: FMC DIO card channel 2 (LA16)
set_property PACKAGE_PIN Y12 [get_ports diff_in_p_2]
set_property IOSTANDARD LVDS [get_ports diff_in_p_2]
set_property PACKAGE_PIN AA12 [get_ports diff_in_n_2]
set_property IOSTANDARD LVDS [get_ports diff_in_n_2]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_p_2]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_n_2]

# Channel 3: FMC DIO card channel 3 (LA03)
set_property PACKAGE_PIN Y2 [get_ports diff_in_p_3]
set_property IOSTANDARD LVDS [get_ports diff_in_p_3]
set_property PACKAGE_PIN Y1 [get_ports diff_in_n_3]
set_property IOSTANDARD LVDS [get_ports diff_in_n_3]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_p_3]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_n_3]

# Calibration input: FMC DIO card channel 4 (LA00_CC).
set_property PACKAGE_PIN Y4 [get_ports cal_in_p]
set_property IOSTANDARD LVDS [get_ports cal_in_p]
set_property PACKAGE_PIN Y3 [get_ports cal_in_n]
set_property IOSTANDARD LVDS [get_ports cal_in_n]
set_property DIFF_TERM_ADV TERM_100 [get_ports cal_in_p]
set_property DIFF_TERM_ADV TERM_100 [get_ports cal_in_n]

# Channel control pins: oe = output enable, term = termination enable
set_property PACKAGE_PIN V6  [get_ports {oe[0]}]
set_property PACKAGE_PIN K12 [get_ports {oe[1]}]
set_property PACKAGE_PIN Y9  [get_ports {oe[2]}]
set_property PACKAGE_PIN AB6 [get_ports {oe[3]}]
set_property PACKAGE_PIN AB3 [get_ports {oe[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {oe[*]}]

set_property PACKAGE_PIN U6  [get_ports {term[0]}]
set_property PACKAGE_PIN AC1 [get_ports {term[1]}]
set_property PACKAGE_PIN AC3 [get_ports {term[2]}]
set_property PACKAGE_PIN W2  [get_ports {term[3]}]
set_property PACKAGE_PIN W1  [get_ports {term[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {term[*]}]

# Input monitor LEDs: input channels 0, 1, 2 on ZCU102 GPIO_LED_5, 6, 7
# (channel 3 has none). Each LED is on while its input is above the threshold.
set_property PACKAGE_PIN AH13 [get_ports {led_in[0]}]
set_property PACKAGE_PIN AH14 [get_ports {led_in[1]}]
set_property PACKAGE_PIN AL12 [get_ports {led_in[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_in[*]}]

# NOTE: sel_0 and led_4[4:0] from the old const_ZCU.xdc are intentionally
# omitted -- they belong to the old architecture and are not used in the
# unified design. They do not affect timing.

# =============================================================================
# 2. CDC FALSE PATHS & MAX DELAY
# =============================================================================

# A. The raw hits act as asynchronous clocks.
create_clock -period 10.000 -name hit_0_clk [get_ports diff_in_p_0]
create_clock -period 10.000 -name hit_1_clk [get_ports diff_in_p_1]
create_clock -period 10.000 -name hit_2_clk [get_ports diff_in_p_2]
create_clock -period 10.000 -name hit_3_clk [get_ports diff_in_p_3]
create_clock -period 10.000 -name cal_clk   [get_ports cal_in_p]
set_clock_groups -asynchronous -group [get_clocks hit_0_clk]
set_clock_groups -asynchronous -group [get_clocks hit_1_clk]
set_clock_groups -asynchronous -group [get_clocks hit_2_clk]
set_clock_groups -asynchronous -group [get_clocks hit_3_clk]
set_clock_groups -asynchronous -group [get_clocks cal_clk]

# B. Relax timing across the 100MHz/400MHz boundary (manual synchronizers).
# Clock names are obtained from the actual PS and MMCM pins in the generated
# Vivado design; the old pl_clk0/clk_fast_400 names did not exist in this run.
set clk_sys [get_clocks clk_pl_0]
set clk_fast [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */mmcme4_adv_inst/CLKOUT0}]]
set_max_delay -datapath_only -from $clk_sys  -to $clk_fast 10.0
set_max_delay -datapath_only -from $clk_fast -to $clk_sys  10.0

# =============================================================================
# 3. TDL PHYSICAL PLACEMENT (PBLOCKS)
# =============================================================================

# Two pblocks per delay line, so it can only be placed one way: the chain
# (100 CARRY8 and its capture flip-flops) exactly in rows 20..119 of its
# column, and the launch flip-flop (with the channel's input mux, in the start
# line) in rows 16..19 just below, where the edge enters the chain. With one
# 120-row pblock the placer sometimes put a chain at Y0..Y99 with the launch
# flip-flop above it, differently from build to build. (A LOC on the first
# CARRY8 made placement fail.)
# EXCLUDE_PLACEMENT keeps all other logic out of these columns; without it a
# stray cell in a 100-row pblock stops the chain from fitting.

# ------ CHANNEL 0 ------
create_pblock pblock_ch0_start
add_cells_to_pblock [get_pblocks pblock_ch0_start] \
    [get_cells -hier -filter {NAME =~ *gen_channels[0].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch0_start] -add {SLICE_X46Y20:SLICE_X46Y119}
set_property IS_SOFT false [get_pblocks pblock_ch0_start]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch0_start]

create_pblock pblock_ch0_start_launch
add_cells_to_pblock [get_pblocks pblock_ch0_start_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[0].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch0_start_launch] -add {SLICE_X46Y16:SLICE_X46Y19}
set_property IS_SOFT false [get_pblocks pblock_ch0_start_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch0_start_launch]

create_pblock pblock_ch0_stop
add_cells_to_pblock [get_pblocks pblock_ch0_stop] \
    [get_cells -hier -filter {NAME =~ *gen_channels[0].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch0_stop] -add {SLICE_X47Y20:SLICE_X47Y119}
set_property IS_SOFT false [get_pblocks pblock_ch0_stop]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch0_stop]

create_pblock pblock_ch0_stop_launch
add_cells_to_pblock [get_pblocks pblock_ch0_stop_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[0].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch0_stop_launch] -add {SLICE_X47Y16:SLICE_X47Y19}
set_property IS_SOFT false [get_pblocks pblock_ch0_stop_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch0_stop_launch]

# ------ CHANNEL 1 ------
create_pblock pblock_ch1_start
add_cells_to_pblock [get_pblocks pblock_ch1_start] \
    [get_cells -hier -filter {NAME =~ *gen_channels[1].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch1_start] -add {SLICE_X48Y20:SLICE_X48Y119}
set_property IS_SOFT false [get_pblocks pblock_ch1_start]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch1_start]

create_pblock pblock_ch1_start_launch
add_cells_to_pblock [get_pblocks pblock_ch1_start_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[1].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch1_start_launch] -add {SLICE_X48Y16:SLICE_X48Y19}
set_property IS_SOFT false [get_pblocks pblock_ch1_start_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch1_start_launch]

create_pblock pblock_ch1_stop
add_cells_to_pblock [get_pblocks pblock_ch1_stop] \
    [get_cells -hier -filter {NAME =~ *gen_channels[1].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch1_stop] -add {SLICE_X49Y20:SLICE_X49Y119}
set_property IS_SOFT false [get_pblocks pblock_ch1_stop]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch1_stop]

create_pblock pblock_ch1_stop_launch
add_cells_to_pblock [get_pblocks pblock_ch1_stop_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[1].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch1_stop_launch] -add {SLICE_X49Y16:SLICE_X49Y19}
set_property IS_SOFT false [get_pblocks pblock_ch1_stop_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch1_stop_launch]

# ------ CHANNEL 2 ------
create_pblock pblock_ch2_start
add_cells_to_pblock [get_pblocks pblock_ch2_start] \
    [get_cells -hier -filter {NAME =~ *gen_channels[2].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch2_start] -add {SLICE_X50Y20:SLICE_X50Y119}
set_property IS_SOFT false [get_pblocks pblock_ch2_start]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch2_start]

create_pblock pblock_ch2_start_launch
add_cells_to_pblock [get_pblocks pblock_ch2_start_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[2].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch2_start_launch] -add {SLICE_X50Y16:SLICE_X50Y19}
set_property IS_SOFT false [get_pblocks pblock_ch2_start_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch2_start_launch]

create_pblock pblock_ch2_stop
add_cells_to_pblock [get_pblocks pblock_ch2_stop] \
    [get_cells -hier -filter {NAME =~ *gen_channels[2].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch2_stop] -add {SLICE_X51Y20:SLICE_X51Y119}
set_property IS_SOFT false [get_pblocks pblock_ch2_stop]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch2_stop]

create_pblock pblock_ch2_stop_launch
add_cells_to_pblock [get_pblocks pblock_ch2_stop_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[2].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch2_stop_launch] -add {SLICE_X51Y16:SLICE_X51Y19}
set_property IS_SOFT false [get_pblocks pblock_ch2_stop_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch2_stop_launch]

# ------ CHANNEL 3 ------
create_pblock pblock_ch3_start
add_cells_to_pblock [get_pblocks pblock_ch3_start] \
    [get_cells -hier -filter {NAME =~ *gen_channels[3].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch3_start] -add {SLICE_X52Y20:SLICE_X52Y119}
set_property IS_SOFT false [get_pblocks pblock_ch3_start]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch3_start]

create_pblock pblock_ch3_start_launch
add_cells_to_pblock [get_pblocks pblock_ch3_start_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[3].inst_channel/inst_tdl_start/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch3_start_launch] -add {SLICE_X52Y16:SLICE_X52Y19}
set_property IS_SOFT false [get_pblocks pblock_ch3_start_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch3_start_launch]

create_pblock pblock_ch3_stop
add_cells_to_pblock [get_pblocks pblock_ch3_stop] \
    [get_cells -hier -filter {NAME =~ *gen_channels[3].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && REF_NAME !~ GND && REF_NAME !~ VCC && NAME !~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch3_stop] -add {SLICE_X53Y20:SLICE_X53Y119}
set_property IS_SOFT false [get_pblocks pblock_ch3_stop]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch3_stop]

create_pblock pblock_ch3_stop_launch
add_cells_to_pblock [get_pblocks pblock_ch3_stop_launch] \
    [get_cells -hier -filter {NAME =~ *gen_channels[3].inst_channel/inst_tdl_stop/* && IS_PRIMITIVE && NAME =~ *inst_launch_fdc*}]
resize_pblock [get_pblocks pblock_ch3_stop_launch] -add {SLICE_X53Y16:SLICE_X53Y19}
set_property IS_SOFT false [get_pblocks pblock_ch3_stop_launch]
set_property EXCLUDE_PLACEMENT true [get_pblocks pblock_ch3_stop_launch]

# =============================================================================
# 4. ASYNCHRONOUS HIT ROUTING CONSTRAINTS
# =============================================================================
# Prevent Vivado from routing the raw hits onto global clock trees. The
# calibration input is a hit too. (The input mux ends up in the LUT in front
# of each launch flip-flop, as the stop line's inverter already was.)
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ *u_tdc_top/hit_i*}]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ *u_tdc_top/cal_hit_i*}]
