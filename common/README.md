# Shared test infrastructure

Helpers functions

| File | Functions |
| --- | --- |
| `board.tcl` | FPGA part and environment overrides |
| `build.tcl` | Sequential runs, VIO configuration, optional reports, routing/timing checks |
| `hardware.tcl` | JTAG target/device validation, volatile programming, disconnection |
| `probes.py` | LTX VIO paths and net names exported as Tcl dictionaries |
| `vio.tcl` | Resolve hardware probes and read hexadecimal values |

`build::run name ?args...?` launches one run with `-jobs 1` and checks completion.
`build::check_implementation reports` writes routing, DRC and timing reports,
requiring complete routing and nonnegative setup/hold slack.
`build::create_vio name inputs outputs` takes lists of probe widths.
DDR4 and GTY call `build::check_synchronizers` on the implemented design.

JTAG callers use:

```tcl
set device [hardware::connect $ltx]
try {
    hardware::program $device $bitfile
    refresh_hw_device $device
} finally {
    hardware::close
}
```

Omit `$ltx` for designs without probes. Connection requires one matching target
and one `xcvu13p`. `HW_SERVER_URL` defaults to `localhost:3121`, `JTAG_TARGET`
to `*Digilent*`. PCIe removal/rescanning stays manual,
see [XDMA programming](../xdma/README.md#program).

`rtl/sync_bus.v` synchronizes independent levels with configurable `WIDTH`,
`STAGES` (at least two), and `INIT`. It does not ensure coherent multi-bit
transfers or capture short pulses. `rtl/sync_bus.xdc` excludes first-stage
inputs from timing and requires matching registers.
