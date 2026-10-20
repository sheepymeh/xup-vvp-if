# XUP-VVP GTY bringup

PRBS31 at 25.78125 Gb/s on 32 channels, excluding PCIe quads. Supports internal
PMA loopback and external fixtures or cables between ports on this card.

## Build and program

Builds require Vivado 2025.2 and Python 3. Hardware uses 322.265625 MHz reference clocks.
Run from this directory with a fresh `build/` after source changes:

```sh
vivado -mode batch -nojournal -log build.log -source build.tcl
vivado -mode batch -nojournal -log program.log -source hardware.tcl -tclargs program
```

`board.json` and `quad.v.in` generate `build/top.v`, `build/constraints.xdc` and
`build/mapping.tcl`. Edit those sources rather than generated files.
Routing and setup/hold timing must pass before writing `build/all_channels.bit`
and `build/all_channels.ltx`. Reports are in `build/reports/`, and
`build/probes.tcl` maps VIO probes using the [shared helpers](../common/README.md).

When leaving an active XDMA image, first remove its PCIe function manually,
see [XDMA programming](../xdma/README.md#program).

## Internal test

```sh
vivado -mode batch -nojournal -log test.log -source hardware.tcl -tclargs test
```

All 32 lanes must acquire readiness and PRBS lock, detect injected errors in
native counters and sticky flags, then pass a concurrent 120-second soak.
Verified on this card with zero errors during the soak.

## External test

External operation remains unvalidated without fixtures.

A port name selects a self-loop fixture, `PORT:PEER` selects a duplex cable.
Ports are `QSFP0`–`QSFP3` (four lanes each) and `SlimSAS1`/`SlimSAS2` (eight each).
Multiple independent connections can run together:

```sh
vivado -mode batch -nojournal -log external.log -source hardware.tcl -tclargs external QSFP0
vivado -mode batch -nojournal -log external.log -source hardware.tcl -tclargs external QSFP0:QSFP3 SlimSAS1:SlimSAS2
```

The test tries RX polarity inversion where needed, then injects errors into
one TX lane at a time. Each must reach exactly one RX on its declared peer
port, with agreeing native counters and sticky flags. Discovery prints:

```text
LANE_MAP=TX:QSFP0.0(q233/lane0),RX:QSFP3.2(q228/lane2),rx_inverted:1
```

Labels identify logical FPGA lanes, not connector contacts. Mapping includes
board and cable routing, physical port assignments still need confirmation
with known fixtures. This tests raw serial PRBS, not Ethernet or SAS.

## Results

Both modes finish with per-lane counters and `RESULT=PASS` only after injection
checks and a 120-second error-free soak. Faults and timeouts abort.
PRBS remains active after exit. Sticky flags capture errors and interruptions
between reads. A watchdog detects RX clock loss within about 0.41 ms, provided
its reference-derived control clock is still running.
