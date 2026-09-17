library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tdc_top is
    Generic (
        G_NUM_CHANNELS : integer := 2;
        G_PACKET_SIZE  : integer := 90
    );
    Port (
        clk_fast_i    : in  std_logic;
        clk_sys_i     : in  std_logic;

        rst_i         : in  std_logic;
        en_i          : in  std_logic;

        hit_i         : in  std_logic_vector(G_NUM_CHANNELS - 1 downto 0);

        fifo_overflow_count_o : out std_logic_vector(31 downto 0);

        m_axis_tdata  : out std_logic_vector(127 downto 0);
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

    type data_array_t is array (0 to G_NUM_CHANNELS - 1) of std_logic_vector(127 downto 0);
    signal ch_data           : data_array_t;
    signal ch_valid          : std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    signal ch_ready          : std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    signal ch_overflow_pulse : std_logic_vector(G_NUM_CHANNELS - 1 downto 0);

    signal overflow_counter : unsigned(31 downto 0) := (others => '0');

    signal arbiter_idx  : integer range 0 to G_NUM_CHANNELS - 1 := 0;
    signal packet_count : unsigned(15 downto 0) := (others => '0');

    type state_t is (S_POLL, S_SEND, S_POP_FIFO);
    signal state : state_t := S_POLL;

begin

    process(clk_fast_i)
        variable any_overflow : std_logic;
    begin
        if rising_edge(clk_fast_i) then
            if rst_i = '1' then
                global_coarse_time <= (others => '0');
                overflow_counter   <= (others => '0');
                en_fast_meta       <= '0';
                en_fast_sync       <= '0';
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
            end if;
        end if;
    end process;

    global_coarse_slv     <= std_logic_vector(global_coarse_time);
    fifo_overflow_count_o <= std_logic_vector(overflow_counter);

    gen_channels: for i in 0 to G_NUM_CHANNELS - 1 generate
        inst_channel : entity work.tdc_channel
            generic map ( G_CHANNEL_ID => i )
            port map (
                clk_fast_i       => clk_fast_i,
                clk_sys_i        => clk_sys_i,
                rst_i            => rst_i,
                en_i             => en_fast_sync,
                global_time_i    => global_coarse_slv,
                hit_i            => hit_i(i),
                data_o           => ch_data(i),
                valid_o          => ch_valid(i),
                ready_i          => ch_ready(i),
                overflow_pulse_o => ch_overflow_pulse(i)
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
                            if arbiter_idx = G_NUM_CHANNELS - 1 then
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
                        if arbiter_idx = G_NUM_CHANNELS - 1 then
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
