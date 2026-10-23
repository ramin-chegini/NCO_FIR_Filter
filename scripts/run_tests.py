#!/usr/bin/env python3
"""Run portable RTL regressions with GHDL or Vivado XSim (Python stdlib only)."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [ROOT / name for name in (
    "tests/ip_models.vhd", "HDL/programmble_Dec.vhd", "HDL/TopM.vhd",
    "tests/tb_decimator.vhd", "tests/tb_topm.vhd",
)]


def run(command, cwd, expected=None):
    print("+", subprocess.list2cmdline([str(arg) for arg in command]), flush=True)
    # Windows requires cmd.exe to invoke vendor .bat entry points.
    arguments = [str(arg) for arg in command]
    if os.name == "nt":
        # Batch files otherwise split NAME=value at '=' in their %* expansion.
        arguments = " ".join('"' + arg + '"' if "=" in arg and '"' not in arg
                             else subprocess.list2cmdline([arg]) for arg in arguments)
    result = subprocess.run(arguments, cwd=cwd,
                            text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, shell=os.name == "nt")
    print(result.stdout, end="", flush=True)
    if expected:
        if expected not in result.stdout or "PASS tb_topm" in result.stdout:
            raise RuntimeError("Negative test did not detect the expected FIR stall")
    elif result.returncode:
        raise RuntimeError(f"Command failed with exit code {result.returncode}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", choices=("auto", "ghdl", "xsim"), default="auto")
    parser.add_argument("--vivado-bin", type=Path, help="Vivado bin directory if absent from PATH")
    args = parser.parse_args()
    simulator = args.simulator
    if simulator == "auto":
        simulator = "ghdl" if shutil.which("ghdl") else "xsim"
    work = ROOT / "build" / "tests" / simulator
    work.mkdir(parents=True, exist_ok=True)
    if simulator == "ghdl":
        ghdl = shutil.which("ghdl")
        if not ghdl:
            raise RuntimeError("GHDL is not on PATH")
        run([ghdl, "-a", "--std=08", *SOURCES], work)
        for top in ("tb_decimator", "tb_topm"):
            run([ghdl, "-e", "--std=08", top], work)
            output = run([ghdl, "-r", "--std=08", top, "--assert-level=error", "--stop-time=2ms"], work)
            if f"PASS {top}" not in output:
                raise RuntimeError(f"{top} did not finish")
        run([ghdl, "-r", "--std=08", "tb_topm", "-gINJECT_STALL=true", "--assert-level=error"],
            work, expected="FIR input stalled")
    else:
        def vendor_tool(name):
            suffix = ".bat" if os.name == "nt" else ""
            path = args.vivado_bin / (name + suffix) if args.vivado_bin else shutil.which(name)
            if not path or not Path(path).is_file():
                raise RuntimeError("Vivado tools not found; pass --vivado-bin or use --simulator ghdl")
            return path
        run([vendor_tool("xvhdl"), "--2008", *SOURCES], work)
        for top in ("tb_decimator", "tb_topm"):
            run([vendor_tool("xelab"), f"work.{top}", "-s", top], work)
            output = run([vendor_tool("xsim"), top, "-runall"], work)
            if f"PASS {top}" not in output:
                raise RuntimeError(f"{top} did not finish")
        run([vendor_tool("xelab"), "work.tb_topm", "-generic_top", "INJECT_STALL=true",
             "-s", "tb_topm_stall"], work)
        run([vendor_tool("xsim"), "tb_topm_stall", "-runall"], work, expected="FIR input stalled")
    print("PASS: RTL regressions and expected-stall detection")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
