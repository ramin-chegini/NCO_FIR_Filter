-- Real-input digital downconverter: DDS -> signed I/Q mixers -> FIR -> selector.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TopM is
    generic (
        -- Disable the three ILA cores for normal synthesis to save resources.
        ENABLE_DEBUG : boolean := false
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        input_data       : in  std_logic_vector(15 downto 0);
        fir_load_valid   : in  std_logic;
        fir_config_valid : in  std_logic;
        fir_coe_data     : in  std_logic_vector(15 downto 0);
        fir_coe_last     : in  std_logic;
        NCO_factor_valid : in  std_logic;
        NCO_factor       : in  std_logic_vector(31 downto 0);
        Dec_factor       : in  std_logic_vector(7 downto 0);
        Dec_factor_valid : in  std_logic;
        fir_load_ready   : out std_logic;
        fir_config_ready : out std_logic;
        fir_out          : out std_logic_vector(95 downto 0);
        out_valid_dec    : out std_logic;
        out_Im           : out std_logic_vector(44 downto 0);
        out_re           : out std_logic_vector(44 downto 0)
    );
end entity TopM;

architecture behavioral of TopM is
    component fir_coef_load is
        port (
            aclk                            : in  std_logic;
            aresetn                         : in  std_logic;
            s_axis_data_tvalid              : in  std_logic;
            s_axis_data_tready              : out std_logic;
            s_axis_data_tdata               : in  std_logic_vector(47 downto 0);
            s_axis_config_tvalid            : in  std_logic;
            s_axis_config_tready            : out std_logic;
            s_axis_config_tdata             : in  std_logic_vector(7 downto 0);
            s_axis_reload_tvalid            : in  std_logic;
            s_axis_reload_tready            : out std_logic;
            s_axis_reload_tlast             : in  std_logic;
            s_axis_reload_tdata             : in  std_logic_vector(15 downto 0);
            m_axis_data_tvalid              : out std_logic;
            m_axis_data_tdata               : out std_logic_vector(95 downto 0);
            event_s_reload_tlast_missing    : out std_logic;
            event_s_reload_tlast_unexpected : out std_logic
        );
    end component;

    component dds_NCO is
        port (
            aclk                 : in  std_logic;
            aresetn              : in  std_logic;
            s_axis_config_tvalid : in  std_logic;
            s_axis_config_tdata  : in  std_logic_vector(31 downto 0);
            m_axis_data_tvalid   : out std_logic;
            m_axis_data_tdata    : out std_logic_vector(31 downto 0)
        );
    end component;

    component mult_16_bit is
        port (
            CLK : in  std_logic;
            A   : in  std_logic_vector(15 downto 0);
            B   : in  std_logic_vector(15 downto 0);
            CE  : in  std_logic;
            P   : out std_logic_vector(22 downto 0)
        );
    end component;

    component ila_0 is
        port (
            clk     : in std_logic;
            probe0  : in std_logic_vector(15 downto 0);
            probe1  : in std_logic_vector(15 downto 0);
            probe2  : in std_logic_vector(22 downto 0);
            probe3  : in std_logic_vector(22 downto 0);
            probe4  : in std_logic_vector(23 downto 0);
            probe5  : in std_logic_vector(23 downto 0);
            probe6  : in std_logic_vector(0 downto 0);
            probe7  : in std_logic_vector(0 downto 0);
            probe8  : in std_logic_vector(0 downto 0);
            probe9  : in std_logic_vector(15 downto 0);
            probe10 : in std_logic_vector(15 downto 0);
            probe11 : in std_logic_vector(44 downto 0);
            probe12 : in std_logic_vector(44 downto 0);
            probe13 : in std_logic_vector(44 downto 0);
            probe14 : in std_logic_vector(44 downto 0);
            probe15 : in std_logic_vector(0 downto 0)
        );
    end component;

    component ila_3 is
        port (
            clk    : in std_logic;
            probe0 : in std_logic_vector(0 downto 0);
            probe1 : in std_logic_vector(0 downto 0);
            probe2 : in std_logic_vector(31 downto 0);
            probe3 : in std_logic_vector(0 downto 0);
            probe4 : in std_logic_vector(15 downto 0)
        );
    end component;

    signal reset_n          : std_logic;
    signal dds_valid        : std_logic;
    signal dds_data         : std_logic_vector(31 downto 0);
    signal mixed_re         : std_logic_vector(22 downto 0);
    signal mixed_im         : std_logic_vector(22 downto 0);
    signal padded_re        : std_logic_vector(23 downto 0);
    signal padded_im        : std_logic_vector(23 downto 0);
    signal mixed_data       : std_logic_vector(47 downto 0);
    signal mixer_valid      : std_logic := '0';
    signal fir_input_valid  : std_logic;
    signal fir_input_ready  : std_logic;
    signal fir_valid        : std_logic;
    signal fir_data         : std_logic_vector(95 downto 0);
    signal reload_missing   : std_logic;
    signal reload_unexpected: std_logic;
    signal dec_re           : std_logic_vector(44 downto 0);
    signal dec_im           : std_logic_vector(44 downto 0);
begin
    reset_n <= not rst;

    ins_dds : dds_NCO
        port map (
            aclk                 => clk,
            aresetn              => reset_n,
            s_axis_config_tvalid => NCO_factor_valid,
            s_axis_config_tdata  => NCO_factor,
            m_axis_data_tvalid   => dds_valid,
            m_axis_data_tdata    => dds_data
        );

    -- Both signed multipliers retain product bits 31:9 and have one register
    -- (IP PipeStages=1). Delay validity by the same clock, including bubbles.
    process(clk, rst)
    begin
        if rst = '1' then
            mixer_valid <= '0';
        elsif rising_edge(clk) then
            mixer_valid <= dds_valid;
        end if;
    end process;
    fir_input_valid <= mixer_valid and reset_n;

    mult_re : mult_16_bit
        port map (CLK => clk, A => dds_data(15 downto 0),
                  B => input_data, CE => '1', P => mixed_re);
    mult_im : mult_16_bit
        port map (CLK => clk, A => dds_data(31 downto 16),
                  B => input_data, CE => '1', P => mixed_im);

    -- Each 23-bit signed path occupies a byte-aligned 24-bit AXI slot.
    padded_re  <= std_logic_vector(resize(signed(mixed_re), 24));
    padded_im  <= std_logic_vector(resize(signed(mixed_im), 24));
    mixed_data <= padded_im & padded_re;

    ins_fir : fir_coef_load
        port map (
            aclk                            => clk,
            aresetn                         => reset_n,
            s_axis_data_tvalid              => fir_input_valid,
            s_axis_data_tready              => fir_input_ready,
            s_axis_data_tdata               => mixed_data,
            s_axis_config_tvalid            => fir_config_valid,
            s_axis_config_tready            => fir_config_ready,
            s_axis_config_tdata             => (others => '0'),
            s_axis_reload_tvalid            => fir_load_valid,
            s_axis_reload_tready            => fir_load_ready,
            s_axis_reload_tlast             => fir_coe_last,
            s_axis_reload_tdata             => fir_coe_data,
            m_axis_data_tvalid              => fir_valid,
            m_axis_data_tdata               => fir_data,
            event_s_reload_tlast_missing    => reload_missing,
            event_s_reload_tlast_unexpected => reload_unexpected
        );

    inst_decimator : entity work.decimator
        generic map (ENABLE_DEBUG => ENABLE_DEBUG)
        port map (
            clk => clk, rst => rst, fir_data => fir_data, fir_valid => fir_valid,
            dec_factor => Dec_factor, dec_factor_valid => Dec_factor_valid,
            data_out_re => dec_re, data_out_Im => dec_im,
            data_valid => out_valid_dec
        );

    -- This legacy input interface is a continuous real-time stream with no
    -- ready port. Reconfigurations must not stall the FIR data channel.
    -- synthesis translate_off
    process(clk)
    begin
        if rising_edge(clk) and rst = '0' then
            assert not (fir_input_valid = '1' and fir_input_ready = '0')
                report "FIR input stalled: continuous input samples will be lost"
                severity failure;
            assert reload_missing /= '1' and reload_unexpected /= '1'
                report "FIR coefficient reload packet has incorrect TLAST"
                severity warning;
        end if;
    end process;
    -- synthesis translate_on

    debug_enabled : if ENABLE_DEBUG generate
        ila_dds : ila_3
            port map (
                clk => clk, probe0(0) => reset_n, probe1(0) => NCO_factor_valid,
                probe2 => NCO_factor, probe3(0) => dds_valid,
                probe4 => dds_data(15 downto 0)
            );
        ila_NCO_fir : ila_0
            port map (
                clk => clk, probe0 => dds_data(15 downto 0),
                probe1 => dds_data(31 downto 16), probe2 => mixed_re,
                probe3 => mixed_im, probe4 => padded_re, probe5 => padded_im,
                probe6(0) => fir_input_valid, probe7(0) => fir_valid,
                probe8(0) => dds_valid, probe9 => dds_data(15 downto 0),
                probe10 => input_data, probe11 => dec_re, probe12 => dec_im,
                probe13 => fir_data(92 downto 48),
                probe14 => fir_data(44 downto 0), probe15(0) => rst
            );
    end generate;

    out_re  <= dec_re;
    out_Im  <= dec_im;
    fir_out <= fir_data;
end architecture behavioral;
