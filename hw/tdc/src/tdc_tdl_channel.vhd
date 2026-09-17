library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity tdc_tdl_channel is
    Generic (
        G_NUM_CARRY8       : integer := 100;
        G_SACRIFICIAL_BLKS : integer := 2;
        G_INVERT           : boolean := false
    );
    Port (
        clk_fast_i : in  std_logic;
        rst_i      : in  std_logic;
        hit_i      : in  std_logic;
        taps_o     : out std_logic_vector(((G_NUM_CARRY8 - G_SACRIFICIAL_BLKS) * 8) - 1 downto 0)
    );
end tdc_tdl_channel;

architecture rtl of tdc_tdl_channel is
    signal carry_cascade : std_logic_vector(G_NUM_CARRY8 - 1 downto 0);
    signal hit_launched  : std_logic;
    signal hit_anchored  : std_logic;
    signal taps_q : std_logic_vector(((G_NUM_CARRY8 - G_SACRIFICIAL_BLKS) * 8) - 1 downto 0) := (others => '1');
begin

    inst_launch_fdc : FDC
    generic map ( INIT => '0' )
    port map (
        Q   => hit_launched,
        C   => hit_i,
        CLR => rst_i,
        D   => '1'
    );

    gen_anchor_non_invert: if not G_INVERT generate
        inst_hit_anchor : LUT1
        generic map ( INIT => "10" )
        port map ( O => hit_anchored, I0 => hit_launched );
    end generate;

    gen_anchor_invert: if G_INVERT generate
        inst_hit_anchor : LUT1
        generic map ( INIT => "01" )
        port map ( O => hit_anchored, I0 => hit_launched );
    end generate;

    gen_carry_chain: for i in 0 to G_NUM_CARRY8 - 1 generate
        signal carry_out_local : std_logic_vector(7 downto 0);
        signal tap_out_local   : std_logic_vector(7 downto 0);
        signal s_input         : std_logic_vector(7 downto 0);
    begin
        s_input <= "1111111" & hit_anchored;

        gen_first_carry: if i = 0 generate
            inst_carry8_first : CARRY8
            generic map ( CARRY_TYPE => "SINGLE_CY8" )
            port map (
                CO     => carry_out_local,
                O      => tap_out_local,
                CI     => '1',
                CI_TOP => '0',
                DI     => x"00",
                S      => s_input
            );
        end generate gen_first_carry;

        gen_next_carry: if i > 0 generate
            inst_carry8_next : CARRY8
            generic map ( CARRY_TYPE => "SINGLE_CY8" )
            port map (
                CO     => carry_out_local,
                O      => tap_out_local,
                CI     => carry_cascade(i-1),
                CI_TOP => '0',
                DI     => x"00",
                S      => x"FF"
            );
        end generate gen_next_carry;

        carry_cascade(i) <= carry_out_local(7);

        gen_capture: if i >= G_SACRIFICIAL_BLKS generate
            gen_capture_taps: for j in 0 to 7 generate
                inst_fdpe : FDPE
                generic map ( INIT => '1' )
                port map (
                    Q   => taps_q(((i - G_SACRIFICIAL_BLKS) * 8) + j),
                    C   => clk_fast_i,
                    CE  => taps_q(0),
                    PRE => rst_i,
                    D   => tap_out_local(j)
                );
            end generate gen_capture_taps;
        end generate gen_capture;
    end generate gen_carry_chain;

    taps_o <= taps_q;

end rtl;
