library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_topm is
    generic (INJECT_STALL : boolean := false);
end entity;

architecture test of tb_topm is
    signal clk, rst, nco_valid, factor_valid, config_valid : std_logic := '0';
    signal sample : std_logic_vector(15 downto 0) := (others => '0');
    signal nco : std_logic_vector(31 downto 0) := (others => '0');
    signal factor : std_logic_vector(7 downto 0) := x"01";
    signal load_ready, config_ready, output_valid : std_logic;
    signal raw_data : std_logic_vector(95 downto 0);
    signal output_re, output_im : std_logic_vector(44 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.TopM
        port map (clk => clk, rst => rst, input_data => sample,
                  fir_load_valid => '0', fir_config_valid => config_valid,
                  fir_coe_data => (others => '0'), fir_coe_last => '0',
                  NCO_factor_valid => nco_valid, NCO_factor => nco,
                  Dec_factor => factor, Dec_factor_valid => factor_valid,
                  fir_load_ready => load_ready, fir_config_ready => config_ready,
                  fir_out => raw_data, out_valid_dec => output_valid,
                  out_Im => output_im, out_re => output_re);

    stimulus : process
        variable dds_word : std_logic_vector(31 downto 0) := (others => '0');
        variable dds_v, mix_v, fir_v : std_logic := '0';
        variable mixed_re, mixed_im : signed(44 downto 0) := (others => '0');
        variable expected_fir : std_logic_vector(95 downto 0) := (others => '0');
        variable expected_re, expected_im : std_logic_vector(44 downto 0) := (others => '0');
        variable product_re, product_im : signed(31 downto 0);
        variable next_fir : std_logic_vector(95 downto 0);
        variable next_output_valid : std_logic;
        variable checks : natural := 0;
        procedure reset_dut is
        begin
            wait until falling_edge(clk);
            rst <= '1';
            nco_valid <= '0';
            factor_valid <= '0';
            wait for 2 ns;
            assert output_valid = '0' and signed(output_re) = 0 and signed(output_im) = 0
                report "Top-level reset did not clear outputs" severity failure;
            wait until falling_edge(clk);
            rst <= '0';
            factor_valid <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            factor_valid <= '0';
            dds_v := '0'; mix_v := '0'; fir_v := '0';
            dds_word := (others => '0');
            expected_fir := (others => '0');
            expected_re := (others => '0'); expected_im := (others => '0');
        end procedure;
    begin
        for epoch in 0 to 1 loop
            reset_dut;
            for i in 0 to 299 loop
                wait until falling_edge(clk);
                sample <= std_logic_vector(to_signed(((i * 7919) mod 65536) - 32768, 16));
                nco <= std_logic_vector(to_signed(((i * 2131) mod 65536) - 32768, 16)) &
                       std_logic_vector(to_signed(((i * 3571) mod 65536) - 32768, 16));
                nco_valid <= '0';
                if i mod 7 < 4 then nco_valid <= '1'; end if;
                if INJECT_STALL and i = 10 then config_valid <= '1'; end if;
                wait until rising_edge(clk);
                -- Independent three-stage reference: stimulus DDS register,
                -- signed product / 512, and one-cycle FIR pass-through model.
                next_output_valid := fir_v;
                if fir_v = '1' then
                    expected_re := expected_fir(44 downto 0);
                    expected_im := expected_fir(92 downto 48);
                end if;
                next_fir := expected_fir;
                if mix_v = '1' then
                    next_fir := "000" & std_logic_vector(mixed_im) &
                                "000" & std_logic_vector(mixed_re);
                end if;
                product_re := signed(dds_word(15 downto 0)) * signed(sample);
                product_im := signed(dds_word(31 downto 16)) * signed(sample);
                mixed_re := resize(shift_right(product_re, 9), 45);
                mixed_im := resize(shift_right(product_im, 9), 45);
                fir_v := mix_v;
                mix_v := dds_v;
                dds_v := nco_valid;
                dds_word := nco;
                expected_fir := next_fir;
                wait for 1 ns;
                assert raw_data = expected_fir report "Mixer/FIR data or pipeline alignment mismatch" severity failure;
                assert output_valid = next_output_valid report "Top-level validity mismatch" severity failure;
                assert output_re = expected_re and output_im = expected_im
                    report "Top-level signed I/Q mismatch" severity failure;
                assert load_ready = '1' and config_ready = '1'
                    report "Reload/config ready ports are not connected" severity failure;
                checks := checks + 1;
            end loop;
        end loop;
        assert not INJECT_STALL report "Expected stall assertion did not fire" severity failure;
        report "PASS tb_topm: " & natural'image(checks) & " cycles with signed extremes, bubbles and reset" severity note;
        finish;
    end process;
end architecture;
