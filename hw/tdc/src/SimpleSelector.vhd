library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity SimpleSelector is
    Port (
        sel    : in  STD_LOGIC;
        switch : out STD_LOGIC_VECTOR (4 downto 0)
    );
end SimpleSelector;

architecture Behavioral of SimpleSelector is
begin

    switch <= "11111" when sel = '0' else
              "00000";

end Behavioral;
