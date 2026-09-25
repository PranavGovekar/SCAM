# =========================================================================
# TDC constraints -- restored from the previously working const_ZCU.xdc
# pinout/timing/placement, adapted to the unified base architecture.
# =========================================================================

# =========================================================================
# 1. I/O CONSTRAINTS
# =========================================================================
set_property PACKAGE_PIN AB4 [get_ports led_0]
set_property IOSTANDARD LVCMOS18 [get_ports led_0]
set_property PACKAGE_PIN AG14 [get_ports led_1]
set_property IOSTANDARD LVCMOS33 [get_ports led_1]
set_property PACKAGE_PIN AF13 [get_ports led_2]
set_property IOSTANDARD LVCMOS33 [get_ports led_2]
set_property PACKAGE_PIN AE13 [get_ports led_3]
set_property IOSTANDARD LVCMOS33 [get_ports led_3]

set_property PACKAGE_PIN T7 [get_ports diff_out_p_0]
set_property IOSTANDARD LVDS [get_ports diff_out_p_0]
set_property PACKAGE_PIN T6 [get_ports diff_out_n_0]
set_property IOSTANDARD LVDS [get_ports diff_out_n_0]

set_property PACKAGE_PIN AA2 [get_ports diff_out_p_1]
set_property IOSTANDARD LVDS [get_ports diff_out_p_1]
set_property PACKAGE_PIN AA1 [get_ports diff_out_n_1]
set_property IOSTANDARD LVDS [get_ports diff_out_n_1]

set_property PACKAGE_PIN V12 [get_ports diff_in_p_0]
set_property IOSTANDARD LVDS [get_ports diff_in_p_0]
set_property PACKAGE_PIN V11 [get_ports diff_in_n_0]
set_property IOSTANDARD LVDS [get_ports diff_in_n_0]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_p_0]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_n_0]

set_property PACKAGE_PIN N13 [get_ports diff_in_p_1]
set_property IOSTANDARD LVDS [get_ports diff_in_p_1]
set_property PACKAGE_PIN M13 [get_ports diff_in_n_1]
set_property IOSTANDARD LVDS [get_ports diff_in_n_1]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_p_1]
set_property DIFF_TERM_ADV TERM_100 [get_ports diff_in_n_1]

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

# NOTE: sel_0 and led_4[4:0] from the old const_ZCU.xdc are intentionally
# omitted -- they belong to the old architecture and are not used in the
# unified design. They do not affect timing.

# =============================================================================
# 2. CDC FALSE PATHS & MAX DELAY
# =============================================================================

# A. The raw hits act as asynchronous clocks.
create_clock -period 10.000 -name hit_0_clk [get_ports diff_in_p_0]
create_clock -period 10.000 -name hit_1_clk [get_ports diff_in_p_1]
set_clock_groups -asynchronous -group [get_clocks hit_0_clk]
set_clock_groups -asynchronous -group [get_clocks hit_1_clk]

# B. Relax timing across the 100MHz/400MHz boundaries (manual synchronizers).
set_max_delay -datapath_only -from [get_clocks pl_clk0]      -to [get_clocks clk_fast_400] 10.0
set_max_delay -datapath_only -from [get_clocks clk_fast_400] -to [get_clocks pl_clk0]      10.0

# =============================================================================
# 3. TDL PHYSICAL PLACEMENT (PBLOCKS)
# =============================================================================

# ------ CHANNEL 0 ------
create_pblock pblock_ch0_start
add_cells_to_pblock [get_pblocks pblock_ch0_start] \
    [get_cells -hier -filter {NAME =~ *gen_channels[0].inst_channel*inst_tdl_start*}]
resize_pblock [get_pblocks pblock_ch0_start] -add {SLICE_X46Y0:SLICE_X46Y119}
set_property IS_SOFT false [get_pblocks pblock_ch0_start]

create_pblock pblock_ch0_stop
add_cells_to_pblock [get_pblocks pblock_ch0_stop] \
    [get_cells -hier -filter {NAME =~ *gen_channels[0].inst_channel*inst_tdl_stop*}]
resize_pblock [get_pblocks pblock_ch0_stop] -add {SLICE_X47Y0:SLICE_X47Y119}
set_property IS_SOFT false [get_pblocks pblock_ch0_stop]

# ------ CHANNEL 1 ------
create_pblock pblock_ch1_start
add_cells_to_pblock [get_pblocks pblock_ch1_start] \
    [get_cells -hier -filter {NAME =~ *gen_channels[1].inst_channel*inst_tdl_start*}]
resize_pblock [get_pblocks pblock_ch1_start] -add {SLICE_X48Y0:SLICE_X48Y119}
set_property IS_SOFT false [get_pblocks pblock_ch1_start]

create_pblock pblock_ch1_stop
add_cells_to_pblock [get_pblocks pblock_ch1_stop] \
    [get_cells -hier -filter {NAME =~ *gen_channels[1].inst_channel*inst_tdl_stop*}]
resize_pblock [get_pblocks pblock_ch1_stop] -add {SLICE_X49Y0:SLICE_X49Y119}
set_property IS_SOFT false [get_pblocks pblock_ch1_stop]

# =============================================================================
# 4. ASYNCHRONOUS HIT ROUTING CONSTRAINTS
# =============================================================================
# Prevent Vivado from routing the raw hits onto global clock trees.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ *hit_i*}]
