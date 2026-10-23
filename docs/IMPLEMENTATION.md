# Implementation and review notes

## Arithmetic and packing

The DDS has a 32-bit programmable phase increment and an 8-cycle configured latency. Its 16-bit cosine and negative-sine outputs multiply the current signed 16-bit input. Each multiplier has **one pipeline register** and exports bits **31 down to 9** of the signed 32-bit product. The nine discarded low bits are truncated without rounding or saturation. The wrapper preserves this existing numerical scaling.

Each 23-bit product is sign-extended into a 24-bit byte-aligned FIR input slot. The real path occupies `[22:0]`, with a sign copy in bit 23; the imaginary path occupies `[46:24]`, with a sign copy in bit 47. The multiplier-valid register delays DDS validity by one clock, matching the multiplier latency.

The FIR has two parallel signed paths, 50 taps per path, 16-bit integer coefficients, 23-bit integer input, and a configured 45-bit full-precision output. It operates at a single rate with coefficient reload enabled. The output slots are 48 bits each: real sample `[44:0]` and imaginary sample `[92:48]`. Padding bits `[47:45]` and `[95:93]` are ignored. The decimator preserves these signed 45-bit samples without further scaling.

IP settings and coefficient files are authoritative for regenerated latency and arithmetic. If multiplier `PipeStages`, FIR widths, or path counts change, update the wrapper and tests together.

## Correctness fixes

| Finding in the original RTL | Change |
| --- | --- |
| Reset assigned output ports while the clocked path assigned internal signals; concurrent assignments drove the same ports again. | Each output now has a single internal register driver, including reset. |
| Reset was read by a process sensitive only to `clk`. | Asynchronous-reset processes explicitly include `rst` in their sensitivity list. |
| The existing synthesis report contained 91 latches and multi-driven-net critical warnings. | Reset and normal operation update the same registers; the build script checks for inferred latches after synthesis. |
| FIR input valid bypassed the one-cycle multiplier pipeline. | DDS validity is delayed one cycle and masked during reset. |
| Factor zero underflowed the `factor - 1` comparison, effectively selecting every 256 samples. | Zero is explicitly normalized to factor one. |
| Changing the factor retained the previous count, potentially waiting for counter wraparound. | Updates restart the group; a simultaneous valid sample uses the new factor. |
| An ILA probe read an undriven FIR-valid signal. | The probe now observes the actual delayed FIR input-valid signal. |
| Mixed `std_logic_unsigned` and `numeric_std`, unused declarations, and commented-out implementations obscured behavior. | Use only standard `numeric_std` arithmetic and remove unused code. |

## Resource changes

The build script aligns each IP's standalone synthesis clock constraint with the top-level 128 MHz clock. The original interface metadata used 100 MHz for the DDS/FIR and 10 MHz for the multipliers, despite a 128 MHz datapath configuration. The clock-interface properties follow [AMD UG896](https://docs.amd.com/r/2021.1-English/ug896-vivado-ip/Setting-the-Target-Clock-Period).

`ENABLE_DEBUG` defaults to `false` and controls all three ILA instances. Enable it explicitly for hardware debugging. Removing analyzers from a normal build avoids their capture-memory and debug-logic costs; exact savings require comparing complete implementation reports for the two variants.

The decimator caches `N-1` when a configuration word arrives and uses an 8-bit countdown and zero test on each valid sample. This removes the runtime `counter = factor - 1` expression from the sample path. The factor register used only by the debug probes is optimized away when debugging is disabled.

The supplied coefficients are symmetric, but the FIR configuration intentionally remains `Non_Symmetric` because arbitrary coefficient reload is part of the interface. Restricting all reload sets to symmetric coefficients could enable a different FIR architecture; that change requires a defined coefficient contract and separate numerical/resource validation.

## Stream and reset contracts

All signals are synchronous to the same clock except assertion of the custom active-high reset. The integration must synchronize reset release and hold reset long enough for the vendor cores.

The ADC input has no ready or valid ports. It represents an uninterrupted sample stream. DDS startup validity qualifies the mixer; no attempt is made to pause the external sample source. The supplied FIR is configured for 128 Msamples/s at a 128 MHz clock. If its input `TREADY` drops during valid traffic, samples cannot be retained by this interface. A simulation failure reports that condition. A fully stallable design would require an explicit input handshake, upstream flow control, and corresponding DDS/sample alignment.

Reload and configuration are separate AXI-stream handshakes. The source must keep payload/valid/last stable until acceptance. A reload becomes active through a subsequent configuration synchronization event, as specified in [AMD PG149](https://docs.amd.com/r/en-US/pg149-fir-compiler/RELOAD-Channel). The wrapper reports missing or unexpected reload `TLAST` events as simulation warnings. It does not repair malformed packets.

Decimation is sample selection after filtering. For each factor N, the preceding filter must attenuate frequencies above the new Nyquist frequency. The filename `fir_nco_40Mbw.coe` does not establish a verified passband or stopband specification, and one fixed coefficient set need not be suitable for every factor.

## Verification scope

`tb_decimator` uses an independent count-up reference to check all 256 factor encodings, output hold, signed lane extraction, input gaps, reset, and deterministic mixed reconfiguration traffic. `tb_topm` checks signed products, truncation, slot padding, validity bubbles, and reset through the wrapper using explicitly simplified DDS/FIR doubles. A negative test confirms that an injected FIR stall is detected.

The Vivado build regenerates the actual IP from the text customizations and can synthesize the complete design. No board pinout or I/O delays are supplied, so synthesis reports do not establish board timing closure. Hardware validation, vendor-IP numerical response tests, and analog/RF filter specifications remain integration work.

### Recorded local results (2026-10-23)

Vivado/XSim 2025.2 passed `tb_decimator` with 68,921 valid input samples and all 256 factor values, and `tb_topm` with 600 checked cycles. The injected-stall regression produced the expected assertion failure and was accepted by the runner.

The release build regenerated and synthesized the actual vendor IP, with zero synthesis errors, zero critical warnings, and zero inferred latches. Its expanded synthesis utilization was 2,459 LUTs, 7,052 registers, 100 DSPs, and 2 block-RAM tiles. Remaining warnings include intentionally unused FIR padding bits, removal of the debug-only factor register, vendor-generated scoped constraints, and clock-period rounding.

The release timing report is **before placement and routing**: setup WNS was +4.114 ns and hold WHS was -0.123 ns. Therefore the timing report does not pass all checks. It also identifies missing input/output delay constraints. Complete board constraints and implementation are required before making a timing-closure claim.
