library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Quiescent AXI4-Stream master used by the base template and CT design.
entity axis_idle_source is
    port (
        aclk          : in  std_logic;
        m_axis_tdata  : out std_logic_vector(127 downto 0);
        m_axis_tkeep  : out std_logic_vector(15 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic
    );
end entity axis_idle_source;

architecture rtl of axis_idle_source is
    attribute X_INTERFACE_INFO : string;
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
    attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF M_AXIS";
begin
    m_axis_tdata  <= (others => '0');
    m_axis_tkeep  <= (others => '0');
    m_axis_tvalid <= '0';
    m_axis_tlast  <= '0';
end architecture rtl;
