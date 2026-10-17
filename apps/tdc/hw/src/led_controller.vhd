library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity led_controller is
    Port (
        clk    : in  STD_LOGIC;
        enable : in  STD_LOGIC;
        led    : out STD_LOGIC_VECTOR(4 downto 0)
    );
end led_controller;

architecture Behavioral of led_controller is

    constant CLK_FREQ_HZ      : integer := 100_000_000;
    constant NUM_STATES       : integer := 20;
    constant SEQ_PERIOD_S_x2  : integer := 2;
    constant CYCLES_PER_STATE : integer := (CLK_FREQ_HZ * SEQ_PERIOD_S_x2) / NUM_STATES;

    type led_pattern_t is array (0 to NUM_STATES - 1) of STD_LOGIC_VECTOR(4 downto 0);

    constant LED_PATTERNS : led_pattern_t := (
        0  => "00000",
        1  => "10000",
        2  => "11000",
        3  => "01000",
        4  => "01100",
        5  => "00100",
        6  => "00110",
        7  => "00010",
        8  => "00011",
        9  => "00001",
        10 => "00000",
        11 => "00001",
        12 => "00011",
        13 => "00010",
        14 => "00110",
        15 => "00100",
        16 => "01100",
        17 => "01000",
        18 => "11000",
        19 => "10000"
    );

    signal clk_counter : integer range 0 to CYCLES_PER_STATE - 1 := 0;
    signal state_index : integer range 0 to NUM_STATES - 1      := 0;

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if enable = '0' then
                clk_counter <= 0;
                state_index <= 0;
            else
                if clk_counter = CYCLES_PER_STATE - 1 then
                    clk_counter <= 0;
                    if state_index = NUM_STATES - 1 then
                        state_index <= 0;
                    else
                        state_index <= state_index + 1;
                    end if;
                else
                    clk_counter <= clk_counter + 1;
                end if;
            end if;
        end if;
    end process;

    led <= LED_PATTERNS(state_index) when enable = '1' else "00000";

end Behavioral;
