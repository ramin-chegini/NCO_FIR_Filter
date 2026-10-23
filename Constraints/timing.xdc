# The supplied DDS and FIR are configured for a 128 MHz sample/clock rate.
# Board-specific pins, I/O standards, and I/O delays belong in the integrator's XDC.
create_clock -name sample_clk -period 7.8125 [get_ports clk]
