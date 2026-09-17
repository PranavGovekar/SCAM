library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity se_to_diff_1ch is
    port (
        se_in      : in  std_logic;

        diff_out_p : out std_logic;
        diff_out_n : out std_logic
    );
end se_to_diff_1ch;

architecture Structural of se_to_diff_1ch is

begin

    OBUFDS_inst : OBUFDS
        port map (
            I  => se_in,
            O  => diff_out_p,
            OB => diff_out_n
        );

end Structural;
