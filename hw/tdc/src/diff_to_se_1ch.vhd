library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity diff_to_se_1ch is
    port (
        diff_in_p : in  std_logic;
        diff_in_n : in  std_logic;

        se_out    : out std_logic
    );
end diff_to_se_1ch;

architecture Structural of diff_to_se_1ch is

begin

    IBUFDS_inst : IBUFDS
        port map (
            I  => diff_in_p,
            IB => diff_in_n,
            O  => se_out
        );

end Structural;
