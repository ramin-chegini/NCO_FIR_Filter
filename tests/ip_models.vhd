-- Test doubles for wrapper verification only. These are NOT DDS/FIR algorithms.
-- Never add this file to a synthesis or vendor-IP simulation fileset.
library ieee;
use ieee.std_logic_1164.all;
entity dds_NCO is
    port (aclk, aresetn, s_axis_config_tvalid : in std_logic;
          s_axis_config_tdata : in std_logic_vector(31 downto 0);
          m_axis_data_tvalid : out std_logic;
          m_axis_data_tdata : out std_logic_vector(31 downto 0));
end entity;
architecture model of dds_NCO is
begin
    -- Deliberately allow validity bubbles and data changes on invalid cycles.
    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            m_axis_data_tvalid <= '0';
            m_axis_data_tdata <= (others => '0');
        elsif rising_edge(aclk) then
            m_axis_data_tvalid <= s_axis_config_tvalid;
            m_axis_data_tdata <= s_axis_config_tdata;
        end if;
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity mult_16_bit is
    port (CLK : in std_logic; A, B : in std_logic_vector(15 downto 0);
          CE : in std_logic; P : out std_logic_vector(22 downto 0));
end entity;
architecture model of mult_16_bit is
begin
    process(CLK)
        variable product : signed(31 downto 0);
    begin
        if rising_edge(CLK) and CE = '1' then
            product := signed(A) * signed(B);
            P <= std_logic_vector(product(31 downto 9));
        end if;
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity fir_coef_load is
    port (aclk, aresetn, s_axis_data_tvalid : in std_logic;
          s_axis_data_tready : out std_logic;
          s_axis_data_tdata : in std_logic_vector(47 downto 0);
          s_axis_config_tvalid : in std_logic;
          s_axis_config_tready : out std_logic;
          s_axis_config_tdata : in std_logic_vector(7 downto 0);
          s_axis_reload_tvalid : in std_logic;
          s_axis_reload_tready : out std_logic;
          s_axis_reload_tlast : in std_logic;
          s_axis_reload_tdata : in std_logic_vector(15 downto 0);
          m_axis_data_tvalid : out std_logic;
          m_axis_data_tdata : out std_logic_vector(95 downto 0);
          event_s_reload_tlast_missing, event_s_reload_tlast_unexpected : out std_logic);
end entity;
architecture model of fir_coef_load is
begin
    -- Configuration VALID injects a stall for the separate negative test.
    s_axis_data_tready <= aresetn and not s_axis_config_tvalid;
    s_axis_config_tready <= aresetn;
    s_axis_reload_tready <= aresetn;
    event_s_reload_tlast_missing <= '0';
    event_s_reload_tlast_unexpected <= '0';
    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            m_axis_data_tvalid <= '0';
            m_axis_data_tdata <= (others => '0');
        elsif rising_edge(aclk) then
            m_axis_data_tvalid <= s_axis_data_tvalid and not s_axis_config_tvalid;
            if s_axis_data_tvalid = '1' and s_axis_config_tvalid = '0' then
                assert s_axis_data_tdata(23) = s_axis_data_tdata(22) and
                       s_axis_data_tdata(47) = s_axis_data_tdata(46)
                    report "Mixer slot padding is not sign extended" severity failure;
                m_axis_data_tdata <=
                    "000" & std_logic_vector(resize(signed(s_axis_data_tdata(46 downto 24)), 45)) &
                    "000" & std_logic_vector(resize(signed(s_axis_data_tdata(22 downto 0)), 45));
            end if;
        end if;
    end process;
end architecture;
