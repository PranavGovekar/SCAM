library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tdc_therm_encoder is
    Port (
        clk_fast_i  : in  std_logic;
        rst_i       : in  std_logic;
        start_enc_i : in  std_logic;
        taps_in     : in  std_logic_vector(783 downto 0);
        bin_out     : out std_logic_vector(9 downto 0);
        valid_o     : out std_logic
    );
end tdc_therm_encoder;

architecture rtl of tdc_therm_encoder is

    attribute DONT_TOUCH : string;

    type sum_array_stage1_t is array (0 to 15) of unsigned(5 downto 0);
    signal stage1_sums : sum_array_stage1_t;

    type sum_array_stage2_t is array (0 to 3) of unsigned(7 downto 0);
    signal stage2_sums : sum_array_stage2_t;

    signal stage3_sum  : unsigned(9 downto 0);

    attribute DONT_TOUCH of stage1_sums : signal is "TRUE";
    attribute DONT_TOUCH of stage2_sums : signal is "TRUE";
    attribute DONT_TOUCH of stage3_sum  : signal is "TRUE";

    signal valid_p1 : std_logic;
    signal valid_p2 : std_logic;
    signal valid_p3 : std_logic;

begin

    process(clk_fast_i)
        variable chunk_sum : unsigned(5 downto 0);
    begin
        if rising_edge(clk_fast_i) then
            if rst_i = '1' then
                stage1_sums <= (others => (others => '0'));
                stage2_sums <= (others => (others => '0'));
                stage3_sum  <= (others => '0');
                bin_out     <= (others => '0');
                valid_p1    <= '0';
                valid_p2    <= '0';
                valid_p3    <= '0';
                valid_o     <= '0';
            else
                valid_p1 <= start_enc_i;
                valid_p2 <= valid_p1;
                valid_p3 <= valid_p2;
                valid_o  <= valid_p3;

                for i in 0 to 15 loop
                    chunk_sum := (others => '0');
                    for j in 0 to 48 loop
                        if taps_in((i * 49) + j) = '1' then
                            chunk_sum := chunk_sum + 1;
                        end if;
                    end loop;
                    stage1_sums(i) <= chunk_sum;
                end loop;

                for i in 0 to 3 loop
                    stage2_sums(i) <= resize(stage1_sums(i*4 + 0), 8) +
                                      resize(stage1_sums(i*4 + 1), 8) +
                                      resize(stage1_sums(i*4 + 2), 8) +
                                      resize(stage1_sums(i*4 + 3), 8);
                end loop;

                stage3_sum <= resize(stage2_sums(0), 10) +
                              resize(stage2_sums(1), 10) +
                              resize(stage2_sums(2), 10) +
                              resize(stage2_sums(3), 10);

                bin_out <= std_logic_vector(stage3_sum);
            end if;
        end if;
    end process;

end rtl;
