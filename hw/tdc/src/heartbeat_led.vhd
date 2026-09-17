library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity heartbeat_led is
    generic (
        CLK_FREQ_MHZ : integer := 100;
        BLINK_FREQ_HZ : integer := 1
    );
    port (
        clk : in  std_logic;
        rst : in  std_logic;
        led : out std_logic
    );
end heartbeat_led;

architecture Behavioral of heartbeat_led is

    constant MAX_COUNT : integer := (CLK_FREQ_MHZ * 1_000_000) / (2 * BLINK_FREQ_HZ);

    signal counter   : unsigned(31 downto 0);
    signal led_state : std_logic;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                counter <= (others => '0');
                led_state <= '0';
            else
                if counter >= MAX_COUNT - 1 then
                    counter <= (others => '0');
                    led_state <= not led_state;
                else
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;

    led <= led_state;

end Behavioral;
