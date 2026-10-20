# XUP-VVP UDIMM DDR4 bringup

Two independent controllers and JTAG AXI masters

## Build

Run with fresh `build/` directory after source changes:

```sh
vivado -mode batch -nojournal -log build.log -source build.tcl
```

`prepare.sh` downloads GPLv2+ upstream constraints:
* [DIMM0](https://raw.githubusercontent.com/d953i/Custom_Part_Data_Files/b8b941d66658f0c44013fb03469ec142d24db5c9/Boards/Bittware_CVP13/CVP13_DIMM0.xdc),
* [DIMM1](https://raw.githubusercontent.com/d953i/Custom_Part_Data_Files/b8b941d66658f0c44013fb03469ec142d24db5c9/Boards/Bittware_CVP13/CVP13_DIMM1.xdc).
Edit constraint preparation in that script, it regenerates `build/constraints/dimm*.xdc`.

Routing and setup/hold timing must pass before `build/ddr4_test.bit`
and `build/ddr4_test.ltx` are written. Reports are in `build/reports/`, and
`build/probes.tcl` maps VIO probes using the [shared helpers](../common/README.md).

## Program and test

If an XDMA image is active, first remove its [PCIe function](../xdma/README.md#program).

```sh
vivado -mode batch -nojournal -log program.log -source hardware.tcl -tclargs program
vivado -mode batch -nojournal -log test.log -source hardware.tcl -tclargs test both
```

Select `DIMM0`, `DIMM1`, or `both`, only selected sockets need memory.
Both controllers attempt calibration after programming. The test waits up to
60 seconds for selected controllers to calibrate and leave UI reset before
issuing AXI transactions.

Each master addresses its DIMM from zero. The smoke test writes four 32-bit
words at `0x1000`–`0x100F`, then verifies them. DIMM1 uses complemented patterns
to expose aliasing. Success prints `RESULT=PASS,selection:...,bytes_per_DIMM:16`.
This overwrites 16 bytes per selected DIMM and does not test full capacity or
bandwidth.

Programming and debug access were verified with empty slots. Both controllers
reported calibration failure, and `test both` timed out with `status=0` without
issuing AXI transactions. Populated-DIMM calibration and read/write remain unvalidated.

## Empty-slot diagnostics

```sh
vivado -mode batch -nojournal -log diagnose.log -source hardware.tcl -tclargs diagnose
```

Prints detailed MIG reports, startup status, and clock estimates. Expected
startup is EOS/DCI lock high, DCI/system reset low. `DIAGNOSTICS_COMPLETE`
requires startup completion and clock activity, calibration may still fail.

Clock estimates use VIO snapshots two seconds apart and host timestamps.
UI clocks are nominally 300 MHz, CFGMCLK is approximately 50 MHz.
Estimates include JTAG sampling uncertainty.

Three programming cycles consistently completed startup with both UI clocks
near 300 MHz and CFGMCLK near 48.7 MHz. Both calibration processors passed,
then failed DQS-gate training with no memory preamble. BMC reported normal
DIMM rails: 1.19 V supply, 2.53 V VPP, and 0.60 V VTT.

| VIO input | Value |
| --- | --- |
| `probe_in0` | Bits 1:0 calibration complete, bits 3:2 UI reset |
| `probe_in1` | Bits 3:0 system reset, DCI reset, DCI locked, EOS |
| `probe_in2` | DIMM0 UI clock count divided by 2^20 |
| `probe_in3` | DIMM1 UI clock count divided by 2^20 |
| `probe_in4` | Monitor clock cycle count |

## Board mapping and other DIMMs

Candidate memory pins come from CVP-13 constraints and remain physically
unvalidated. Controller labels DIMM0/DIMM1 have not been matched to sockets
J9/J13. Reference inputs are `AY18/AY17` and `BB31/BB32`, nominally 100 MHz.

For another module, rebuild with matching settings:

1. Check SPD/datasheets for module type, ranks, component/data width, capacity,
   voltage, timings and rank mirroring. Confirm board routing supports them,
   changing IP settings cannot add missing rank or ECC wiring.
2. Add matching part data to `BLS4G4D240FSB.csv`, preserving its schema and units.
   If renaming the CSV, update both references in `build.tcl`.
3. In `build.tcl`, select `DDR4_MemoryPart` and review `DDR4_MemoryType`,
   `DDR4_DataWidth`, `DDR4_TimePeriod`, `DDR4_InputClockPeriod` and
   `DDR4_CLKOUT0_DIVIDE`. Input clock follows the board, not the DIMM.
   Validate combinations using Vivado and [AMD PG150](https://docs.amd.com/r/en-US/pg150-ultrascale-memory-ip).
4. Match controller address width, JTAG `M_AXI_ADDR_WIDTH` and
   `assign_bd_address -range` to capacity. The current 32-bit masters expose
   4 GiB each, larger apertures require wider addresses.

The current build applies identical settings to both controllers. Different
modules need separate configurations, including for a populated unselected socket.
