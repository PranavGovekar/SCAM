library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tdc_capture_ctrl is
    Port (
        clk_fast_i     : in  std_logic;
        rst_i          : in  std_logic;
        en_i           : in  std_logic;
        read_done_i    : in  std_logic;
        math_done_i    : in  std_logic;

        taps_start_i   : in  std_logic_vector(783 downto 0);
        taps_stop_i    : in  std_logic_vector(783 downto 0);

        global_time_i  : in  std_logic_vector(47 downto 0);

        tdl_rst_o      : out std_logic;
        shadow_start_o : out std_logic_vector(783 downto 0);
        shadow_stop_o  : out std_logic_vector(783 downto 0);

        start_coarse_o : out std_logic_vector(47 downto 0);
        stop_coarse_o  : out std_logic_vector(47 downto 0);

        encode_start_o : out std_logic;
        encode_stop_o  : out std_logic;
        valid_o        : out std_logic
    );
end tdc_capture_ctrl;

architecture rtl of tdc_capture_ctrl is
    attribute ASYNC_REG     : string;
    attribute SHREG_EXTRACT : string;

    signal en_meta, en_sync               : std_logic;
    signal read_done_meta, read_done_sync : std_logic;

    attribute ASYNC_REG of en_meta, en_sync               : signal is "TRUE";
    attribute ASYNC_REG of read_done_meta, read_done_sync : signal is "TRUE";
    attribute SHREG_EXTRACT of en_meta, en_sync               : signal is "NO";
    attribute SHREG_EXTRACT of read_done_meta, read_done_sync : signal is "NO";

    signal taps_start_p1 : std_logic_vector(783 downto 0);
    signal taps_stop_p1  : std_logic_vector(783 downto 0);
    attribute SHREG_EXTRACT of taps_start_p1, taps_stop_p1 : signal is "NO";

    type fsm_state_t is (S_IDLE, S_ARMED, S_MEASURING, S_WAIT_MATH, S_DATA_READY, S_REARM, S_REARM_WAIT);
    signal state : fsm_state_t;

begin
    process(clk_fast_i)
    begin
        if rising_edge(clk_fast_i) then
            if rst_i = '1' then
                en_meta <= '0'; en_sync <= '0';
                read_done_meta <= '0'; read_done_sync <= '0';
                start_coarse_o <= (others => '0'); stop_coarse_o <= (others => '0');
                encode_start_o <= '0'; encode_stop_o <= '0';
                valid_o <= '0'; tdl_rst_o <= '1';
                shadow_start_o <= (others => '0'); shadow_stop_o <= (others => '0');
                taps_start_p1 <= (others => '0'); taps_stop_p1 <= (others => '0');
                state <= S_IDLE;
            else
                en_meta <= en_i; en_sync <= en_meta;
                read_done_meta <= read_done_i; read_done_sync <= read_done_meta;

                taps_start_p1 <= not taps_start_i;
                taps_stop_p1  <= not taps_stop_i;

                encode_start_o <= '0'; encode_stop_o <= '0';

                if en_sync = '0' then
                    state <= S_IDLE; valid_o <= '0'; tdl_rst_o <= '1';
                else
                    case state is
                        when S_IDLE =>
                            state <= S_REARM;
                        when S_REARM =>
                            tdl_rst_o <= '1'; state <= S_REARM_WAIT;
                        when S_REARM_WAIT =>
                            if taps_start_p1(0) = '1' or taps_stop_p1(0) = '1' then
                                tdl_rst_o <= '1'; state <= S_REARM_WAIT;
                            else
                                tdl_rst_o <= '0'; state <= S_ARMED;
                            end if;
                        when S_ARMED =>
                            tdl_rst_o <= '0';
                            if taps_start_p1(0) = '1' and taps_stop_p1(0) = '1' then
                                shadow_start_o <= taps_start_p1;
                                shadow_stop_o  <= taps_stop_p1;
                                encode_start_o <= '1'; encode_stop_o  <= '1';
                                start_coarse_o <= global_time_i; stop_coarse_o  <= global_time_i;
                                state          <= S_WAIT_MATH;
                            elsif taps_start_p1(0) = '1' then
                                shadow_start_o <= taps_start_p1;
                                encode_start_o <= '1';
                                start_coarse_o <= global_time_i;
                                state          <= S_MEASURING;
                            end if;
                        when S_MEASURING =>
                            if taps_stop_p1(0) = '1' then
                                shadow_stop_o <= taps_stop_p1;
                                encode_stop_o <= '1';
                                stop_coarse_o <= global_time_i;
                                state         <= S_WAIT_MATH;
                            end if;
                        when S_WAIT_MATH =>
                            if math_done_i = '1' then
                                valid_o <= '1'; state   <= S_DATA_READY;
                            end if;
                        when S_DATA_READY =>
                            if read_done_sync = '1' then
                                valid_o <= '0'; state   <= S_REARM;
                            end if;
                        when others =>
                            state <= S_IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;
end rtl;
