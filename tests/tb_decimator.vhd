library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_decimator is
end entity;

architecture test of tb_decimator is
    signal clk, rst, fir_valid, config_valid, data_valid : std_logic := '0';
    signal fir_data : std_logic_vector(95 downto 0) := (others => '0');
    signal factor : std_logic_vector(7 downto 0) := (others => '0');
    signal output_re, output_im : std_logic_vector(44 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.decimator
        port map (clk => clk, rst => rst, fir_data => fir_data,
                  fir_valid => fir_valid, dec_factor => factor,
                  dec_factor_valid => config_valid, data_out_re => output_re,
                  data_out_Im => output_im, data_valid => data_valid);

    stimulus : process
        variable group_size : natural := 2;
        variable accepted : natural := 0;
        variable expected_re, expected_im : std_logic_vector(44 downto 0) := (others => '0');
        variable samples, outputs : natural := 0;
        variable random_bits : unsigned(31 downto 0) := x"8A37C9D1";

        procedure tick(valid : boolean; re, im : integer; new_factor : integer := -1) is
            variable packed : std_logic_vector(95 downto 0) := (others => '1');
            variable expect_valid : std_logic := '0';
        begin
            wait until falling_edge(clk);
            fir_valid <= '0';
            if valid then fir_valid <= '1'; end if;
            packed(44 downto 0) := std_logic_vector(to_signed(re, 45));
            packed(92 downto 48) := std_logic_vector(to_signed(im, 45));
            fir_data <= packed;
            config_valid <= '0';
            if new_factor >= 0 then
                factor <= std_logic_vector(to_unsigned(new_factor, 8));
                config_valid <= '1';
                group_size := new_factor;
                if group_size = 0 then group_size := 1; end if;
                accepted := 0;
            end if;
            if valid then
                samples := samples + 1;
                accepted := accepted + 1;
                if accepted = group_size then
                    accepted := 0;
                    expect_valid := '1';
                    expected_re := packed(44 downto 0);
                    expected_im := packed(92 downto 48);
                    outputs := outputs + 1;
                end if;
            end if;
            wait until rising_edge(clk);
            wait for 1 ns;
            assert data_valid = expect_valid report "Decimation valid/count mismatch" severity failure;
            assert output_re = expected_re and output_im = expected_im
                report "Decimation data mismatch or output changed during an invalid cycle" severity failure;
        end procedure;

        procedure reset_dut is
        begin
            -- Reset between edges, while previously captured data may be nonzero.
            wait until falling_edge(clk);
            wait for 2 ns;
            rst <= '1';
            wait for 1 ns;
            assert data_valid = '0' and signed(output_re) = 0 and signed(output_im) = 0
                report "Asynchronous reset failed" severity failure;
            wait until falling_edge(clk);
            fir_valid <= '0';
            config_valid <= '0';
            rst <= '0';
            group_size := 2;
            accepted := 0;
            expected_re := (others => '0');
            expected_im := (others => '0');
        end procedure;
    begin
        reset_dut;
        tick(true, 101, -101);
        tick(false, 999, 999);
        tick(true, -202, 202);
        -- Every representable factor, including zero, with bubbles and two groups.
        for n in 0 to 255 loop
            tick(true, -32768, 32767, n);
            for i in 1 to 2 * (n + 1) + 3 loop
                tick(true, i * 17, -i * 19);
                if i mod 7 = 0 then tick(false, -999, 999); end if;
            end loop;
        end loop;
        -- Change to a smaller factor partway through a group, then bypass.
        tick(false, 0, 0, 255);
        for i in 1 to 100 loop tick(true, i, -i); end loop;
        tick(true, 333, -333, 2);
        tick(true, 444, -444);
        tick(false, 555, -555, 0);
        tick(true, 666, -666);
        reset_dut;
        -- Deterministic mixed traffic and reconfiguration, checked by a count-up model.
        for i in 1 to 4000 loop
            random_bits := random_bits(30 downto 0) &
                (random_bits(31) xor random_bits(21) xor random_bits(1) xor random_bits(0));
            if random_bits(5 downto 2) = 0 then
                tick(random_bits(0) = '1', i, -i, to_integer(random_bits(15 downto 8)));
            else
                tick(random_bits(0) = '1', i, -i);
            end if;
        end loop;
        reset_dut;
        tick(true, -1, 1);
        tick(true, -2, 2);
        report "PASS tb_decimator: " & natural'image(samples) & " samples, " &
            natural'image(outputs) & " outputs, all 256 factor values" severity note;
        finish;
    end process;
end architecture;
