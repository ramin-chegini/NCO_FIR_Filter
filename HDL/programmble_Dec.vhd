-- Programmable sample selector for the two packed FIR output paths.
-- The legacy filename is retained so existing Vivado projects keep working.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decimator is
    generic (
        ENABLE_DEBUG : boolean := false
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        fir_data         : in  std_logic_vector(95 downto 0);
        fir_valid        : in  std_logic;
        dec_factor       : in  std_logic_vector(7 downto 0);
        dec_factor_valid : in  std_logic;
        data_out_re      : out std_logic_vector(44 downto 0);
        data_out_Im      : out std_logic_vector(44 downto 0);
        data_valid       : out std_logic
    );
end entity decimator;

architecture behavioral of decimator is
    -- Cache N-1 on configuration; the sample path only decrements and tests zero.
    signal period_minus_one : unsigned(7 downto 0) := to_unsigned(1, 8);
    signal remaining        : unsigned(7 downto 0) := to_unsigned(1, 8);
    signal active_factor    : unsigned(7 downto 0) := to_unsigned(2, 8);
    signal output_re        : std_logic_vector(44 downto 0) := (others => '0');
    signal output_im        : std_logic_vector(44 downto 0) := (others => '0');
    signal output_valid     : std_logic := '0';

    component ila_2 is
        port (
            clk    : in std_logic;
            probe0 : in std_logic_vector(0 downto 0);
            probe1 : in std_logic_vector(44 downto 0);
            probe2 : in std_logic_vector(44 downto 0);
            probe3 : in std_logic_vector(0 downto 0);
            probe4 : in std_logic_vector(7 downto 0);
            probe5 : in std_logic_vector(7 downto 0);
            probe6 : in std_logic_vector(95 downto 0)
        );
    end component;
begin
    process(clk, rst)
        variable next_period    : unsigned(7 downto 0);
        variable next_remaining : unsigned(7 downto 0);
        variable factor         : unsigned(7 downto 0);
    begin
        if rst = '1' then
            period_minus_one <= to_unsigned(1, 8);
            remaining        <= to_unsigned(1, 8);
            active_factor    <= to_unsigned(2, 8);
            output_re        <= (others => '0');
            output_im        <= (others => '0');
            output_valid     <= '0';
        elsif rising_edge(clk) then
            output_valid   <= '0';
            next_period    := period_minus_one;
            next_remaining := remaining;

            if dec_factor_valid = '1' then
                factor := unsigned(dec_factor);
                -- Zero is a safe bypass (N=1), never an unsigned underflow.
                if factor = 0 then
                    factor := to_unsigned(1, 8);
                end if;
                active_factor <= factor;
                next_period    := factor - 1;
                next_remaining := next_period;
            end if;

            -- A factor update restarts the group. A simultaneous valid sample
            -- is sample one of the new group; invalid cycles do not count.
            if fir_valid = '1' then
                if next_remaining = 0 then
                    next_remaining := next_period;
                    output_re    <= fir_data(44 downto 0);
                    output_im    <= fir_data(92 downto 48);
                    output_valid <= '1';
                else
                    next_remaining := next_remaining - 1;
                end if;
            end if;

            period_minus_one <= next_period;
            remaining        <= next_remaining;
        end if;
    end process;

    debug_enabled : if ENABLE_DEBUG generate
        ila_decimation : ila_2
            port map (
                clk       => clk,
                probe0(0) => rst,
                probe1    => output_re,
                probe2    => output_im,
                probe3(0) => output_valid,
                probe4    => std_logic_vector(active_factor),
                probe5    => std_logic_vector(remaining),
                probe6    => fir_data
            );
    end generate;

    data_out_re <= output_re;
    data_out_Im <= output_im;
    data_valid  <= output_valid;
end architecture behavioral;
