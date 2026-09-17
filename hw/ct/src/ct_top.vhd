--------------------------------------------------------------------------------
-- ct_top -- platform glue for four_fold_coincidence.
--
-- Responsibilities:
--   * Instantiate 4x diff_to_se_1ch for the differential inputs
--   * Synchronize en_i into the fast clock domain
--   * Decode the 64-bit config word from AXI GPIO into window_width,
--     per-channel delays, pulse_width, sel, and a FIFO pop pulse
--   * Cross the FIFO outputs from clk_fast to clk_axi for AXI GPIO readout
--
-- Config word layout (little-endian, lsb first):
--   [7:0]   window_width
--   [15:8]  delay_A
--   [23:16] delay_B
--   [31:24] delay_C
--   [39:32] delay_D
--   [47:40] pulse_width
--   [51:48] sel
--   [52]    pop pulse (rising edge advances FIFO read pointer)
--
-- FIFO outputs:
--   fifo_dout_l -> gpio_status   (32 bits)
--   fifo_dout_h -> gpio_status2  (32 bits)
--   fifo_flags  -> gpio_flags[1:0] = {fifo_empty, fifo_valid}
--
-- Cross-domain caveat: fifo_dout_l/h are 2FF-synchronized from clk_fast to
-- clk_axi. This is safe for slow rates (up to a few hundred kHz) but not
-- for sustained multi-MHz streaming. For high rates, replace the 2FF sync
-- with an XPM async FIFO.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ct_top is
    port (
        clk_axi     : in  std_logic;   -- 100 MHz, from pl_clk0
        clk_fast    : in  std_logic;   -- 200 MHz, from clk_wiz
        rst         : in  std_logic;   -- active high

        diff_in_p   : in  std_logic_vector(3 downto 0);
        diff_in_n   : in  std_logic_vector(3 downto 0);

        en_i        : in  std_logic;
        config      : in  std_logic_vector(63 downto 0);

        fifo_dout_l : out std_logic_vector(31 downto 0);
        fifo_dout_h : out std_logic_vector(31 downto 0);
        fifo_flags  : out std_logic_vector(1 downto 0);

        coinc_out_o : out std_logic_vector(15 downto 0);
        hw_trig_o   : out std_logic
    );
end ct_top;

architecture rtl of ct_top is

    signal se_a, se_b, se_c, se_d : std_logic;

    signal en_meta, en_sync : std_logic := '0';
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of en_meta : signal is "TRUE";
    attribute ASYNC_REG of en_sync : signal is "TRUE";

    signal window_width : std_logic_vector(7 downto 0);
    signal delay_a      : std_logic_vector(7 downto 0);
    signal delay_b      : std_logic_vector(7 downto 0);
    signal delay_c      : std_logic_vector(7 downto 0);
    signal delay_d      : std_logic_vector(7 downto 0);
    signal pulse_width  : std_logic_vector(7 downto 0);
    signal sel          : std_logic_vector(3 downto 0);
    signal pop_req      : std_logic;

    signal pop_req_s1, pop_req_s2 : std_logic := '0';
    signal pop_prev               : std_logic := '0';
    signal fifo_rd_pulse          : std_logic := '0';

    signal fifo_dout_raw  : std_logic_vector(63 downto 0);
    signal fifo_valid_raw : std_logic;
    signal fifo_empty_raw : std_logic;

    signal fifo_dout_s1, fifo_dout_s2   : std_logic_vector(63 downto 0) := (others => '0');
    signal fifo_valid_s1, fifo_valid_s2 : std_logic := '0';
    signal fifo_empty_s1, fifo_empty_s2 : std_logic := '0';

    signal rst_combined : std_logic;

begin

    -- Differential receivers
    u_diff_a: entity work.diff_to_se_1ch
        port map (diff_in_p => diff_in_p(0), diff_in_n => diff_in_n(0), se_out => se_a);

    u_diff_b: entity work.diff_to_se_1ch
        port map (diff_in_p => diff_in_p(1), diff_in_n => diff_in_n(1), se_out => se_b);

    u_diff_c: entity work.diff_to_se_1ch
        port map (diff_in_p => diff_in_p(2), diff_in_n => diff_in_n(2), se_out => se_c);

    u_diff_d: entity work.diff_to_se_1ch
        port map (diff_in_p => diff_in_p(3), diff_in_n => diff_in_n(3), se_out => se_d);

    -- Enable synchronizer (clk_fast domain)
    process(clk_fast)
    begin
        if rising_edge(clk_fast) then
            en_meta <= en_i;
            en_sync <= en_meta;
        end if;
    end process;

    rst_combined <= rst or (not en_sync);

    -- Config decode (combinational)
    window_width <= config(7 downto 0);
    delay_a      <= config(15 downto 8);
    delay_b      <= config(23 downto 16);
    delay_c      <= config(31 downto 24);
    delay_d      <= config(39 downto 32);
    pulse_width  <= config(47 downto 40);
    sel          <= config(51 downto 48);
    pop_req      <= config(52);

    -- Pop request CDC + rising edge detect, in clk_fast domain
    process(clk_fast)
    begin
        if rising_edge(clk_fast) then
            pop_req_s1 <= pop_req;
            pop_req_s2 <= pop_req_s1;
            pop_prev   <= pop_req_s2;
            if pop_req_s2 = '1' and pop_prev = '0' then
                fifo_rd_pulse <= '1';
            else
                fifo_rd_pulse <= '0';
            end if;
        end if;
    end process;

    -- Trigger core
    u_ct: entity work.four_fold_coincidence
        generic map (SR_DEPTH => 256, FIFO_DEPTH => 512)
        port map (
            clk            => clk_fast,
            rst            => rst_combined,
            in_A           => se_a,
            in_B           => se_b,
            in_C           => se_c,
            in_D           => se_d,
            veto_in        => '0',
            window_width   => window_width,
            delay_A        => delay_a,
            delay_B        => delay_b,
            delay_C        => delay_c,
            delay_D        => delay_d,
            pulse_width    => pulse_width,
            sel            => sel,
            coinc_out      => coinc_out_o,
            hw_trigger_out => hw_trig_o,
            fifo_dout      => fifo_dout_raw,
            fifo_valid     => fifo_valid_raw,
            fifo_empty     => fifo_empty_raw,
            fifo_rd_en     => fifo_rd_pulse
        );

    -- 2FF sync FIFO outputs to clk_axi.
    process(clk_axi)
    begin
        if rising_edge(clk_axi) then
            fifo_dout_s1  <= fifo_dout_raw;
            fifo_dout_s2  <= fifo_dout_s1;
            fifo_valid_s1 <= fifo_valid_raw;
            fifo_valid_s2 <= fifo_valid_s1;
            fifo_empty_s1 <= fifo_empty_raw;
            fifo_empty_s2 <= fifo_empty_s1;
        end if;
    end process;

    fifo_dout_l <= fifo_dout_s2(31 downto 0);
    fifo_dout_h <= fifo_dout_s2(63 downto 32);
    fifo_flags  <= fifo_empty_s2 & fifo_valid_s2;

end rtl;
