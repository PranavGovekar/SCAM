library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tdc_top is
    Generic (
        G_NUM_CHANNELS : integer := 4;
        G_PACKET_SIZE  : integer := 90
    );
    Port (
        clk_fast_i    : in  std_logic;
        clk_sys_i     : in  std_logic;

        rst_i         : in  std_logic;
        en_i          : in  std_logic;

        hit_i         : in  std_logic_vector(G_NUM_CHANNELS - 1 downto 0);

        -- Calibration input (free-running generator), switched onto every
        -- channel in place of hit_i while calibration mode is on.
        cal_hit_i     : in  std_logic;

        fifo_overflow_count_o : out std_logic_vector(31 downto 0);

        -- axi_gpio_config ch1: bit 0 requests calibration mode.
        config_i      : in  std_logic_vector(31 downto 0);
        -- axi_gpio_status2: hits dropped because a calibration FIFO was full.
        cal_status_o  : out std_logic_vector(31 downto 0);
        -- axi_gpio_flags: bit 0 = calibration mode in effect (the switch,
        -- requested by config_i(0), is complete).
        flags_o       : out std_logic_vector(31 downto 0);

        m_axis_tdata  : out std_logic_vector(127 downto 0);
        m_axis_tkeep  : out std_logic_vector(15 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic
    );
end tdc_top;

architecture rtl of tdc_top is

    attribute X_INTERFACE_INFO      : string;
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_INFO      of clk_sys_i : signal is "xilinx.com:signal:clock:1.0 clk_sys_i CLK";
    attribute X_INTERFACE_PARAMETER of clk_sys_i : signal is "ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET rst_i";

    signal en_fast_meta, en_fast_sync : std_logic := '0';
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of en_fast_meta, en_fast_sync : signal is "TRUE";

    signal global_coarse_time : unsigned(47 downto 0) := (others => '0');
    signal global_coarse_slv  : std_logic_vector(47 downto 0);

    -- Arbiter sources: 0 .. G_NUM_CHANNELS-1 are the physics FIFOs, the
    -- next G_NUM_CHANNELS the calibration FIFOs.
    constant C_NUM_SOURCES : integer := 2 * G_NUM_CHANNELS;

    type data_array_t is array (0 to C_NUM_SOURCES - 1) of std_logic_vector(127 downto 0);
    signal ch_data           : data_array_t;
    signal ch_valid          : std_logic_vector(C_NUM_SOURCES - 1 downto 0);
    signal ch_ready          : std_logic_vector(C_NUM_SOURCES - 1 downto 0);
    signal ch_overflow_pulse : std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    signal cal_overflow_pulse : std_logic_vector(G_NUM_CHANNELS - 1 downto 0);

    signal overflow_counter     : unsigned(31 downto 0) := (others => '0');
    signal cal_overflow_counter : unsigned(31 downto 0) := (others => '0');

    -- Calibration mode switch. On a change of the request the channels are
    -- disabled (delay lines held in reset) for C_PAUSE_CYCLES; the input mux
    -- flips C_SWITCH_AT cycles into that, so a glitch from the mux cannot
    -- become a hit. The coarse counter keeps running.
    constant C_PAUSE_CYCLES : integer := 64;
    constant C_SWITCH_AT    : integer := 16;
    signal cal_req_meta, cal_req_sync : std_logic := '0';
    attribute ASYNC_REG of cal_req_meta, cal_req_sync : signal is "TRUE";
    signal cal_sel      : std_logic := '0';
    signal cal_active   : std_logic := '0';
    signal pause_count  : integer range 0 to C_PAUSE_CYCLES := 0;
    signal ch_en        : std_logic := '0';
    signal hit_sel      : std_logic_vector(G_NUM_CHANNELS - 1 downto 0);

    -- Calibration gate, clocked by the generator itself: one generator pulse
    -- in 256 reaches the TDC. The TDC is then always re-armed long before the
    -- pulse arrives, so the clk_fast grid cannot favour any phase (a delay
    -- line released on a clock edge, waiting for the next edge of a periodic
    -- input, weights each phase by how many clock edges fit before it). The
    -- gate changes on the falling edge, so each gated pulse is a whole pulse.
    signal cal_div      : unsigned(7 downto 0) := (others => '0');
    signal cal_gate     : std_logic := '0';
    signal cal_hit_gated : std_logic;

    signal cal_active_meta, cal_active_sync : std_logic := '0';
    attribute ASYNC_REG of cal_active_meta, cal_active_sync : signal is "TRUE";

    signal arbiter_idx  : integer range 0 to C_NUM_SOURCES - 1 := 0;
    signal packet_count : unsigned(15 downto 0) := (others => '0');

    type state_t is (S_POLL, S_SEND, S_POP_FIFO);
    signal state : state_t := S_POLL;

begin

    -- Each TDC word fills all 16 byte lanes; TLAST delimits the packet.
    m_axis_tkeep <= (others => '1');

    process(clk_fast_i)
        variable any_overflow : std_logic;
        variable any_cal_overflow : std_logic;
    begin
        if rising_edge(clk_fast_i) then
            if rst_i = '1' then
                global_coarse_time <= (others => '0');
                overflow_counter   <= (others => '0');
                cal_overflow_counter <= (others => '0');
                en_fast_meta       <= '0';
                en_fast_sync       <= '0';
                cal_req_meta       <= '0';
                cal_req_sync       <= '0';
                cal_sel            <= '0';
                cal_active         <= '0';
                pause_count        <= 0;
                ch_en              <= '0';
            else
                en_fast_meta <= en_i;
                en_fast_sync <= en_fast_meta;

                if en_fast_sync = '1' then
                    global_coarse_time <= global_coarse_time + 1;
                end if;

                any_overflow := '0';
                for i in 0 to G_NUM_CHANNELS - 1 loop
                    if ch_overflow_pulse(i) = '1' then
                        any_overflow := '1';
                    end if;
                end loop;

                if any_overflow = '1' then
                    overflow_counter <= overflow_counter + 1;
                end if;

                any_cal_overflow := '0';
                for i in 0 to G_NUM_CHANNELS - 1 loop
                    if cal_overflow_pulse(i) = '1' then
                        any_cal_overflow := '1';
                    end if;
                end loop;

                if any_cal_overflow = '1' then
                    cal_overflow_counter <= cal_overflow_counter + 1;
                end if;

                cal_req_meta <= config_i(0);
                cal_req_sync <= cal_req_meta;

                if pause_count = 0 then
                    if cal_req_sync /= cal_sel then
                        pause_count <= C_PAUSE_CYCLES;
                    else
                        cal_active <= cal_sel;
                    end if;
                else
                    if pause_count = C_PAUSE_CYCLES - C_SWITCH_AT then
                        cal_sel <= cal_req_sync;
                    end if;
                    pause_count <= pause_count - 1;
                end if;

                if pause_count = 0 and cal_req_sync = cal_sel then
                    ch_en <= en_fast_sync;
                else
                    ch_en <= '0';
                end if;
            end if;
        end if;
    end process;

    global_coarse_slv     <= std_logic_vector(global_coarse_time);
    fifo_overflow_count_o <= std_logic_vector(overflow_counter);
    cal_status_o          <= std_logic_vector(cal_overflow_counter);

    process(cal_hit_i)
    begin
        if falling_edge(cal_hit_i) then
            cal_div <= cal_div + 1;
            if cal_div = 0 then
                cal_gate <= '1';
            else
                cal_gate <= '0';
            end if;
        end if;
    end process;

    cal_hit_gated <= cal_hit_i and cal_gate;

    gen_hit_mux: for i in 0 to G_NUM_CHANNELS - 1 generate
        hit_sel(i) <= cal_hit_gated when cal_sel = '1' else hit_i(i);
    end generate;

    process(clk_sys_i)
    begin
        if rising_edge(clk_sys_i) then
            cal_active_meta <= cal_active;
            cal_active_sync <= cal_active_meta;
        end if;
    end process;

    flags_o <= (0 => cal_active_sync, others => '0');

    gen_channels: for i in 0 to G_NUM_CHANNELS - 1 generate
        inst_channel : entity work.tdc_channel
            generic map ( G_CHANNEL_ID => i )
            port map (
                clk_fast_i       => clk_fast_i,
                clk_sys_i        => clk_sys_i,
                rst_i            => rst_i,
                en_i             => ch_en,
                global_time_i    => global_coarse_slv,
                hit_i            => hit_sel(i),
                data_o           => ch_data(i),
                valid_o          => ch_valid(i),
                ready_i          => ch_ready(i),
                overflow_pulse_o => ch_overflow_pulse(i),
                cal_sel_i            => cal_sel,
                cal_data_o           => ch_data(G_NUM_CHANNELS + i),
                cal_valid_o          => ch_valid(G_NUM_CHANNELS + i),
                cal_ready_i          => ch_ready(G_NUM_CHANNELS + i),
                cal_overflow_pulse_o => cal_overflow_pulse(i)
            );
    end generate;

    process(clk_sys_i)
    begin
        if rising_edge(clk_sys_i) then
            if rst_i = '1' then
                m_axis_tdata  <= (others => '0');
                m_axis_tvalid <= '0';
                m_axis_tlast  <= '0';
                ch_ready      <= (others => '0');
                arbiter_idx   <= 0;
                packet_count  <= (others => '0');
                state         <= S_POLL;
            else
                case state is
                    when S_POLL =>
                        m_axis_tvalid <= '0';
                        m_axis_tlast  <= '0';
                        ch_ready      <= (others => '0');

                        if ch_valid(arbiter_idx) = '1' then
                            m_axis_tdata  <= ch_data(arbiter_idx);
                            m_axis_tvalid <= '1';
                            if packet_count = G_PACKET_SIZE - 1 then
                                m_axis_tlast <= '1';
                            end if;
                            state <= S_SEND;
                        else
                            if arbiter_idx = C_NUM_SOURCES - 1 then
                                arbiter_idx <= 0;
                            else
                                arbiter_idx <= arbiter_idx + 1;
                            end if;
                        end if;

                    when S_SEND =>
                        if m_axis_tready = '1' then
                            ch_ready(arbiter_idx) <= '1';
                            m_axis_tvalid <= '0';
                            m_axis_tlast  <= '0';

                            if packet_count = G_PACKET_SIZE - 1 then
                                packet_count <= (others => '0');
                            else
                                packet_count <= packet_count + 1;
                            end if;
                            state <= S_POP_FIFO;
                        end if;

                    when S_POP_FIFO =>
                        ch_ready(arbiter_idx) <= '0';
                        if arbiter_idx = C_NUM_SOURCES - 1 then
                            arbiter_idx <= 0;
                        else
                            arbiter_idx <= arbiter_idx + 1;
                        end if;
                        state <= S_POLL;
                end case;
            end if;
        end if;
    end process;

end rtl;
