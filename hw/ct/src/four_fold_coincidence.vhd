--------------------------------------------------------------------------------
-- Module  : four_fold_coincidence
-- 4-input multifold coincidence trigger.
-- Generates all 15 unique combinations of 4 inputs plus 1 padding bit.
-- A programmable MUX selects one combination as hw_trigger_out.
-- On each trigger rising edge, a 64-bit {timestamp, coinc} word is written
-- into a synchronous BRAM FIFO.
--
-- Bit mapping of coinc_out:
--   [15] ABCD (padding copy of [14])
--   [14] ABCD  [13] BCD  [12] ACD  [11] ABD  [10] ABC
--   [9]  CD    [8]  BD   [7]  BC   [6]  AD   [5]  AC   [4] AB
--   [3]  D     [2]  C    [1]  B    [0]  A
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity four_fold_coincidence is
    generic (
        SR_DEPTH   : integer := 256;
        FIFO_DEPTH : integer := 512
    );
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;

        in_A           : in  std_logic;
        in_B           : in  std_logic;
        in_C           : in  std_logic;
        in_D           : in  std_logic;

        veto_in        : in  std_logic;

        window_width   : in  std_logic_vector(7 downto 0);

        delay_A        : in  std_logic_vector(7 downto 0);
        delay_B        : in  std_logic_vector(7 downto 0);
        delay_C        : in  std_logic_vector(7 downto 0);
        delay_D        : in  std_logic_vector(7 downto 0);

        pulse_width    : in  std_logic_vector(7 downto 0);

        sel            : in  std_logic_vector(3 downto 0);

        coinc_out      : out std_logic_vector(15 downto 0);

        hw_trigger_out : out std_logic;

        fifo_dout      : out std_logic_vector(63 downto 0);
        fifo_valid     : out std_logic;
        fifo_empty     : out std_logic;
        fifo_rd_en     : in  std_logic
    );
end entity four_fold_coincidence;

architecture rtl of four_fold_coincidence is

    type sr_array is array (0 to SR_DEPTH-1) of std_logic;

    signal sync1_A, sync2_A : std_logic := '0';
    signal sync1_B, sync2_B : std_logic := '0';
    signal sync1_C, sync2_C : std_logic := '0';
    signal sync1_D, sync2_D : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of sync1_A : signal is "TRUE";
    attribute ASYNC_REG of sync2_A : signal is "TRUE";
    attribute ASYNC_REG of sync1_B : signal is "TRUE";
    attribute ASYNC_REG of sync2_B : signal is "TRUE";
    attribute ASYNC_REG of sync1_C : signal is "TRUE";
    attribute ASYNC_REG of sync2_C : signal is "TRUE";
    attribute ASYNC_REG of sync1_D : signal is "TRUE";
    attribute ASYNC_REG of sync2_D : signal is "TRUE";

    signal sr_delay_A : sr_array := (others => '0');
    signal sr_delay_B : sr_array := (others => '0');
    signal sr_delay_C : sr_array := (others => '0');
    signal sr_delay_D : sr_array := (others => '0');

    signal A_delayed : std_logic := '0';
    signal B_delayed : std_logic := '0';
    signal C_delayed : std_logic := '0';
    signal D_delayed : std_logic := '0';

    signal sr_stretch_A : sr_array := (others => '0');
    signal sr_stretch_B : sr_array := (others => '0');
    signal sr_stretch_C : sr_array := (others => '0');
    signal sr_stretch_D : sr_array := (others => '0');

    signal A_wide : std_logic := '0';
    signal B_wide : std_logic := '0';
    signal C_wide : std_logic := '0';
    signal D_wide : std_logic := '0';

    signal coinc_raw : std_logic_vector(15 downto 0) := (others => '0');
    signal coinc_reg : std_logic_vector(15 downto 0) := (others => '0');

    signal mux_out          : std_logic := '0';
    signal mux_out_prev     : std_logic := '0';
    signal rising_det       : std_logic := '0';
    signal pulse_cnt        : unsigned(7 downto 0) := (others => '0');
    signal one_shot         : std_logic := '0';
    signal trigger_out_i    : std_logic := '0';
    signal trigger_out_prev : std_logic := '0';

    signal timestamp : unsigned(47 downto 0) := (others => '0');

    type fifo_mem_t is array (0 to FIFO_DEPTH-1) of std_logic_vector(63 downto 0);
    signal fifo_mem     : fifo_mem_t := (others => (others => '0'));

    signal wr_ptr       : integer range 0 to FIFO_DEPTH-1 := 0;
    signal rd_ptr       : integer range 0 to FIFO_DEPTH-1 := 0;
    signal fifo_count   : integer range 0 to FIFO_DEPTH   := 0;

    signal fifo_wr_en   : std_logic := '0';
    signal fifo_wr_data : std_logic_vector(63 downto 0) := (others => '0');
    signal coinc_latch  : std_logic_vector(15 downto 0) := (others => '0');

    signal fifo_empty_i : std_logic := '1';
    signal fifo_valid_i : std_logic := '0';
    signal fifo_dout_i  : std_logic_vector(63 downto 0) := (others => '0');

begin

    PROC_SYNC : process(clk)
    begin
        if rising_edge(clk) then
            sync1_A <= in_A; sync2_A <= sync1_A;
            sync1_B <= in_B; sync2_B <= sync1_B;
            sync1_C <= in_C; sync2_C <= sync1_C;
            sync1_D <= in_D; sync2_D <= sync1_D;
        end if;
    end process PROC_SYNC;

    PROC_DELAY : process(clk)
    begin
        if rising_edge(clk) then
            sr_delay_A <= sync2_A & sr_delay_A(0 to SR_DEPTH-2);
            sr_delay_B <= sync2_B & sr_delay_B(0 to SR_DEPTH-2);
            sr_delay_C <= sync2_C & sr_delay_C(0 to SR_DEPTH-2);
            sr_delay_D <= sync2_D & sr_delay_D(0 to SR_DEPTH-2);
        end if;
    end process PROC_DELAY;

    A_delayed <= sr_delay_A(to_integer(unsigned(delay_A)));
    B_delayed <= sr_delay_B(to_integer(unsigned(delay_B)));
    C_delayed <= sr_delay_C(to_integer(unsigned(delay_C)));
    D_delayed <= sr_delay_D(to_integer(unsigned(delay_D)));

    PROC_STRETCH : process(clk)
    begin
        if rising_edge(clk) then
            sr_stretch_A <= A_delayed & sr_stretch_A(0 to SR_DEPTH-2);
            sr_stretch_B <= B_delayed & sr_stretch_B(0 to SR_DEPTH-2);
            sr_stretch_C <= C_delayed & sr_stretch_C(0 to SR_DEPTH-2);
            sr_stretch_D <= D_delayed & sr_stretch_D(0 to SR_DEPTH-2);
        end if;
    end process PROC_STRETCH;

    -- Registered wide-signal generation. Clocked to avoid delta-cycle
    -- problems with large shift-register arrays in simulation.
    PROC_WIDE : process(clk)
        variable or_a    : std_logic;
        variable or_b    : std_logic;
        variable or_c    : std_logic;
        variable or_d    : std_logic;
        variable win_int : integer range 1 to SR_DEPTH;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                A_wide <= '0'; B_wide <= '0'; C_wide <= '0'; D_wide <= '0';
            else
                win_int := to_integer(unsigned(window_width));
                if win_int = 0 then win_int := 1; end if;

                or_a := '0'; or_b := '0'; or_c := '0'; or_d := '0';
                for i in 0 to SR_DEPTH-1 loop
                    if i < win_int then
                        or_a := or_a or sr_stretch_A(i);
                        or_b := or_b or sr_stretch_B(i);
                        or_c := or_c or sr_stretch_C(i);
                        or_d := or_d or sr_stretch_D(i);
                    end if;
                end loop;

                A_wide <= or_a; B_wide <= or_b; C_wide <= or_c; D_wide <= or_d;
            end if;
        end if;
    end process PROC_WIDE;

    -- Both 4-fold bits driven directly from the source signals.
    coinc_raw(15) <= A_wide and B_wide and C_wide and D_wide;
    coinc_raw(14) <= A_wide and B_wide and C_wide and D_wide;
    coinc_raw(13) <= B_wide and C_wide and D_wide;
    coinc_raw(12) <= A_wide and C_wide and D_wide;
    coinc_raw(11) <= A_wide and B_wide and D_wide;
    coinc_raw(10) <= A_wide and B_wide and C_wide;
    coinc_raw(9)  <= C_wide and D_wide;
    coinc_raw(8)  <= B_wide and D_wide;
    coinc_raw(7)  <= B_wide and C_wide;
    coinc_raw(6)  <= A_wide and D_wide;
    coinc_raw(5)  <= A_wide and C_wide;
    coinc_raw(4)  <= A_wide and B_wide;
    coinc_raw(3)  <= D_wide;
    coinc_raw(2)  <= C_wide;
    coinc_raw(1)  <= B_wide;
    coinc_raw(0)  <= A_wide;

    PROC_PIPE : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                coinc_reg <= (others => '0');
            else
                coinc_reg <= coinc_raw;
            end if;
        end if;
    end process PROC_PIPE;

    coinc_out <= coinc_reg;

    PROC_TRIGGER : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mux_out        <= '0';
                mux_out_prev   <= '0';
                rising_det     <= '0';
                pulse_cnt      <= (others => '0');
                one_shot       <= '0';
                trigger_out_i  <= '0';
            else
                mux_out      <= coinc_reg(to_integer(unsigned(sel)));
                mux_out_prev <= mux_out;
                rising_det   <= mux_out and (not mux_out_prev);

                if rising_det = '1' then
                    pulse_cnt <= unsigned(pulse_width);
                    one_shot  <= '1';
                elsif pulse_cnt > 0 then
                    pulse_cnt <= pulse_cnt - 1;
                    one_shot  <= '1';
                else
                    one_shot  <= '0';
                end if;

                trigger_out_i <= one_shot and (not veto_in);
            end if;
        end if;
    end process PROC_TRIGGER;

    hw_trigger_out <= trigger_out_i;

    PROC_TIMESTAMP : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                timestamp <= (others => '0');
            else
                timestamp <= timestamp + 1;
            end if;
        end if;
    end process PROC_TIMESTAMP;

    PROC_FIFO_WRITE : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fifo_wr_en       <= '0';
                fifo_wr_data     <= (others => '0');
                coinc_latch      <= (others => '0');
                trigger_out_prev <= '0';
            else
                fifo_wr_en       <= '0';
                trigger_out_prev <= trigger_out_i;

                if trigger_out_i = '1' and trigger_out_prev = '0' then
                    coinc_latch  <= coinc_reg;
                    fifo_wr_data <= std_logic_vector(timestamp) & coinc_reg;
                    fifo_wr_en   <= '1';
                end if;
            end if;
        end if;
    end process PROC_FIFO_WRITE;

    PROC_FIFO : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_ptr       <= 0;
                rd_ptr       <= 0;
                fifo_count   <= 0;
                fifo_valid_i <= '0';
                fifo_empty_i <= '1';
                fifo_dout_i  <= (others => '0');
            else
                fifo_valid_i <= '0';

                if fifo_wr_en = '1' and fifo_count < FIFO_DEPTH then
                    fifo_mem(wr_ptr) <= fifo_wr_data;
                    if wr_ptr = FIFO_DEPTH-1 then
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                end if;

                if fifo_rd_en = '1' and fifo_count > 0 then
                    fifo_dout_i  <= fifo_mem(rd_ptr);
                    fifo_valid_i <= '1';
                    if rd_ptr = FIFO_DEPTH-1 then
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;
                end if;

                if fifo_wr_en = '1' and fifo_rd_en = '0'
                   and fifo_count < FIFO_DEPTH then
                    fifo_count   <= fifo_count + 1;
                    fifo_empty_i <= '0';
                elsif fifo_rd_en = '1' and fifo_wr_en = '0'
                      and fifo_count > 0 then
                    fifo_count <= fifo_count - 1;
                    if fifo_count = 1 then
                        fifo_empty_i <= '1';
                    end if;
                elsif fifo_wr_en = '1' and fifo_rd_en = '1'
                      and fifo_count > 0 and fifo_count < FIFO_DEPTH then
                    fifo_count   <= fifo_count;
                    fifo_empty_i <= '0';
                end if;
            end if;
        end if;
    end process PROC_FIFO;

    fifo_dout  <= fifo_dout_i;
    fifo_valid <= fifo_valid_i;
    fifo_empty <= fifo_empty_i;

end architecture rtl;
