library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity hit_concat is
    Port (
        hit_0_i   : in  std_logic;
        hit_1_i   : in  std_logic;

        hit_bus_o : out std_logic_vector(1 downto 0)
    );
end hit_concat;

architecture rtl of hit_concat is
begin

    hit_bus_o(0) <= hit_0_i;
    hit_bus_o(1) <= hit_1_i;

end rtl;
