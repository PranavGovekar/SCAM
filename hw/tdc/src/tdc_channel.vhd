library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library xpm;
use xpm.vcomponents.all;

entity tdc_channel is
    Generic (
        G_CHANNEL_ID : integer := 0
    );
    Port (
        clk_fast_i       : in  std_logic;
        clk_sys_i        : in  std_logic;
        rst_i            : in  std_logic;
        en_i             : in  std_logic;
        global_time_i    : in  std_logic_vector(47 downto 0);
        hit_i            : in  std_logic;

        data_o           : out std_logic_vector(127 downto 0);
        valid_o          : out std_logic;
        ready_i          : in  std_logic;

        overflow_pulse_o : out std_logic
    );
end tdc_channel;

architecture rtl of tdc_channel is

    signal raw_taps_start    : std_logic_vector(783 downto 0);
    signal raw_taps_stop     : std_logic_vector(783 downto 0);
    signal shadow_start      : std_logic_vector(783 downto 0);
    signal shadow_stop       : std_logic_vector(783 downto 0);

    signal enc_start_trig    : std_logic;
    signal enc_stop_trig     : std_logic;
    signal bin_start_fine    : std_logic_vector(9 downto 0);
    signal bin_stop_fine     : std_logic_vector(9 downto 0);
    signal start_coarse_snap : std_logic_vector(47 downto 0);
    signal stop_coarse_snap  : std_logic_vector(47 downto 0);

    signal start_valid       : std_logic;
    signal stop_valid        : std_logic;
    signal ctrl_valid        : std_logic;
    signal ctrl_valid_q      : std_logic := '0';
    signal read_done_sig     : std_logic := '0';
    signal tdl_rst_ctrl      : std_logic;
    signal hit_i_inv         : std_logic;

    signal fifo_din          : std_logic_vector(127 downto 0);
    signal fifo_wren         : std_logic := '0';
    signal fifo_full         : std_logic;
    signal fifo_empty        : std_logic;

    -- Per-hit write permit -- blocks repeated writes during one pulse.
    signal hit_prev          : std_logic := '0';
    signal write_armed       : std_logic := '0';

begin

    hit_i_inv <= not hit_i;

    inst_tdl_start: entity work.tdc_tdl_channel
        generic map (
            G_NUM_CARRY8       => 100,
            G_SACRIFICIAL_BLKS => 2,
            G_INVERT           => false
        )
        port map (
            clk_fast_i   => clk_fast_i,
            rst_i        => tdl_rst_ctrl,
            hit_i        => hit_i,
            taps_o       => raw_taps_start
        );

    inst_tdl_stop: entity work.tdc_tdl_channel
        generic map (
            G_NUM_CARRY8       => 100,
            G_SACRIFICIAL_BLKS => 2,
            G_INVERT           => false
        )
        port map (
            clk_fast_i   => clk_fast_i,
            rst_i        => tdl_rst_ctrl,
            hit_i        => hit_i_inv,
            taps_o       => raw_taps_stop
        );

    inst_capture_ctrl: entity work.tdc_capture_ctrl
        port map (
            clk_fast_i     => clk_fast_i,
            rst_i          => rst_i,
            en_i           => en_i,
            read_done_i    => read_done_sig,
            math_done_i    => stop_valid,
            taps_start_i   => raw_taps_start,
            taps_stop_i    => raw_taps_stop,
            global_time_i  => global_time_i,

            tdl_rst_o      => tdl_rst_ctrl,
            shadow_start_o => shadow_start,
            shadow_stop_o  => shadow_stop,
            start_coarse_o => start_coarse_snap,
            stop_coarse_o  => stop_coarse_snap,
            encode_start_o => enc_start_trig,
            encode_stop_o  => enc_stop_trig,
            valid_o        => ctrl_valid
        );

    inst_enc_start: entity work.tdc_therm_encoder
        port map (
            clk_fast_i  => clk_fast_i,
            rst_i       => rst_i,
            start_enc_i => enc_start_trig,
            taps_in     => shadow_start,
            bin_out     => bin_start_fine,
            valid_o     => start_valid
        );

    inst_enc_stop: entity work.tdc_therm_encoder
        port map (
            clk_fast_i  => clk_fast_i,
            rst_i       => rst_i,
            start_enc_i => enc_stop_trig,
            taps_in     => shadow_stop,
            bin_out     => bin_stop_fine,
            valid_o     => stop_valid
        );

    process(clk_fast_i)
    begin
        if rising_edge(clk_fast_i) then
            if rst_i = '1' then
                fifo_wren        <= '0';
                fifo_din         <= (others => '0');
                read_done_sig    <= '0';
                ctrl_valid_q     <= '0';
                overflow_pulse_o <= '0';
                hit_prev         <= '0';
                write_armed      <= '0';
            else
                fifo_wren        <= '0';
                overflow_pulse_o <= '0';

                -- Arm on physical hit rising edge
                hit_prev <= hit_i;
                if (hit_i = '1' and hit_prev = '0') then
                    write_armed <= '1';
                end if;

                ctrl_valid_q <= ctrl_valid;

                if (ctrl_valid = '1' and ctrl_valid_q = '0' and write_armed = '1') then
                    write_armed <= '0';
                    if fifo_full = '0' then
                        fifo_din <= std_logic_vector(to_unsigned(G_CHANNEL_ID, 12)) &
                                    stop_coarse_snap  &
                                    bin_stop_fine     &
                                    start_coarse_snap &
                                    bin_start_fine;
                        fifo_wren <= '1';
                    else
                        overflow_pulse_o <= '1';
                    end if;
                end if;

                if ctrl_valid = '1' then
                    read_done_sig <= '1';
                else
                    read_done_sig <= '0';
                end if;
            end if;
        end if;
    end process;

    xpm_fifo_async_inst : xpm_fifo_async
        generic map (
            FIFO_MEMORY_TYPE  => "auto",
            ECC_MODE          => "no_ecc",
            FIFO_WRITE_DEPTH  => 512,
            WRITE_DATA_WIDTH  => 128,
            READ_DATA_WIDTH   => 128,
            PROG_EMPTY_THRESH => 10,
            PROG_FULL_THRESH  => 10,
            READ_MODE         => "fwft",
            USE_ADV_FEATURES  => "0000"
        )
        port map (
            sleep           => '0',
            rst             => rst_i,
            wr_clk          => clk_fast_i,
            wr_en           => fifo_wren,
            din             => fifo_din,
            full            => fifo_full,
            rd_clk          => clk_sys_i,
            rd_en           => ready_i,
            dout            => data_o,
            empty           => fifo_empty,
            injectdbiterr   => '0',
            injectsbiterr   => '0',
            prog_empty      => open,
            prog_full       => open,
            rd_data_count   => open,
            wr_data_count   => open,
            almost_empty    => open,
            almost_full     => open,
            data_valid      => open,
            dbiterr         => open,
            sbiterr         => open,
            overflow        => open,
            underflow       => open,
            wr_ack          => open
        );

    valid_o <= not fifo_empty;

end rtl;
