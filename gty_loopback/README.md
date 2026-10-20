# XUP-VVP GTY bringup

PRBS31 test at 25.78125 Gb/s.
Supports internal PMA loopback on all 32 channels, external self-loop fixtures,
and cables between ports on this card. PCIe quads excluded.

## Build and program

Requires Vivado 2025.2, Python, and 322.265625 MHz reference clocks (see outputs/bwmonitor.txt).

```sh
vivado -mode batch -nojournal -log build.log -source build.tcl
vivado -mode batch -nojournal -log program.log -source hardware.tcl -tclargs program
```

Build from a fresh `build/` directory. Routed setup/hold timing must pass.
Outputs `build/all_channels.bit`, `build/all_channels.ltx` and `build/probes.tcl`.

Programming uses the Digilent JTAG and volatile FPGA SRAM.
The script checks FPGA identity before programming.

## Internal test

```sh
vivado -mode batch -nojournal -log test.log -source hardware.tcl -tclargs test
```

All 32 lanes run concurrently in internal PMA loopback. The test requires
readiness and PRBS lock, verifies injected errors using native counters and
sticky flags, then clears counters and runs a shared 120-second soak.

## External test

_Online testing has **not** be completed due to unpopulated ports_

### Select ports

A bare port name selects a fixture returning that port's TX lanes to its RX
lanes. A `PORT:PEER` connection selects both ports and sends duplex traffic.
QSFP ports have four lanes, SlimSAS ports have eight.

```sh
# One QSFP with a self-loop fixture
vivado -mode batch -nojournal -log external.log -source hardware.tcl -tclargs external QSFP0

# One cable between both SlimSAS ports
vivado -mode batch -nojournal -log external.log -source hardware.tcl -tclargs external SlimSAS1:SlimSAS2

# Test multiple independent cables concurrently
vivado -mode batch -nojournal -log external.log -source hardware.tcl -tclargs external QSFP0:QSFP3 SlimSAS1:SlimSAS2
```

Available ports are `QSFP0`, `QSFP1`, `QSFP2`, `QSFP3`, `SlimSAS1` and
`SlimSAS2`. Unselected ports are ignored.

### Lane discovery and polarity

External mode disables internal loopback. It starts with normal RX polarity,
tries inversion on lanes that did not acquire PRBS lock, then resets RX PMA
and requires all selected lanes to qualify.

To identify lanes, it injects errors into one TX lane at a time, leaving the
other transmitters sending clean PRBS31. Each toggle edge injects an error.
Exactly one selected RX lane must record native errors and a sticky error,
with no readiness interruption. Every selected RX must map uniquely to one
TX on its declared peer port. Lane order within a port is discovered rather
than assumed. Ambiguous responses, missing responses and wrong-port routes
fail. Discovery is sequential, then all selected lanes run the same shared
120-second error-free soak, with checks every ten seconds.

Output includes the measured map and RX polarity correction, for example:

```text
LANE_MAP=TX:QSFP0.0(q233/lane0),RX:QSFP3.2(q228/lane2),rx_inverted:1
```

Labels refer to logical FPGA lanes in `top.v` and `constraints.xdc`, they do
not establish connector contact numbers. Port associations still need physical
confirmation. Polarity correction describes the complete TX-to-RX path, it
does not locate an inversion within the PCB or cable. The map reveals the
combined board and cable routing, a known fixture is needed to isolate board
pinout. This is a raw serial PRBS test, not an Ethernet or SAS protocol test.

## Results and fault detection

Both modes print per-lane final counters and finish with `RESULT=PASS` only
when injection checks and the soak pass. Faults and timeouts abort. PRBS loops
remain active after the script exits. Native PRBS lock indicates acquisition,
subsequent errors are caught by native counters and sticky error flags. A
watchdog detects a stopped shared RX clock within about 0.41 ms. A reference
failure that stops the reference-derived watchdog clock is not independently
timed.
