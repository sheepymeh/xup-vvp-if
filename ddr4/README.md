# XUP-VVP UDIMM DDR4 bringup

A shell script downloads pinned upstream pin constraints on first use, Vivado generates its IP locally.

The offline test builds and checks the implementation without touching the
FPGA. The online test checks calibration, then writes and reads four 32-bit
words at `0x1000`-`0x100F` on each selected DIMM over JTAG. This overwrites
16 bytes per selected DIMM, it is a smoke test rather than a full memory test.

## Offline build

```sh
vivado -mode batch -nojournal -log build.log -source build.tcl
```

The build runs `prepare.sh` to download (GPLv2+):

- [CVP13_DIMM0.xdc](https://raw.githubusercontent.com/d953i/Custom_Part_Data_Files/b8b941d66658f0c44013fb03469ec142d24db5c9/Boards/Bittware_CVP13/CVP13_DIMM0.xdc)
- [CVP13_DIMM1.xdc](https://raw.githubusercontent.com/d953i/Custom_Part_Data_Files/b8b941d66658f0c44013fb03469ec142d24db5c9/Boards/Bittware_CVP13/CVP13_DIMM1.xdc)

The build checks routing, setup and hold timing before writing
`build/ddr4_test.bit` and `build/ddr4_test.ltx`.

`BUILD_COMPLETE, FPGA_NOT_PROGRAMMED` means the implementation passed these
offline checks. It establishes no physical DIMM compatibility, calibration or
memory read/write result.

## Online hardware test

_Online testing has **not** be completed due to unpopulated DIMM slots_

Install compatible DIMMs and update `BLS4G4D240FSB.csv`. Only selected sockets need to be
populated. This fixed memory model is for 4 GiB, single-rank, x64 DDR4-2400
UDIMMs (`BLS4G4D240FSB-2400`), it does not implement ECC or support arbitrary
RDIMMs/LRDIMMs or other densities and rank arrangements.

Program volatile FPGA SRAM once:

```sh
vivado -mode batch -nojournal -log program.log -source hardware.tcl -tclargs program
```

Choose which DIMMs to test, without rebuilding or reprogramming:

```sh
vivado -mode batch -nojournal -log test.log -source hardware.tcl -tclargs test <DIMM0|DIMM1|both>
```

`both` requires both controllers to calibrate, while single-DIMM testing ignores
the other controller's calibration and reset state.

Each controller has a dedicated JTAG AXI master using its own UI clock
Each master maps its DIMM at local address zero.

The script waits up to 60 seconds for selected controllers to calibrate and
leave UI reset before issuing AXI requests.

All selected words are written before verification. DIMM1 uses complemented
patterns to distinguish the two memory paths. A pass ends with
`RESULT=PASS,selection:...,bytes_per_DIMM:16`. It confirms only
the tested locations and sampled calibration state, not full address coverage,
memory bandwidth, signal margin, or absence of brief calibration interruptions.
The hardware path must be validated on all installed DIMMs.

### Board mapping

DIMM0 and DIMM1 are controller names inherited from the existing DDR4 candidate.
Their correspondence to physical sockets J9 and J13 has not been established.
Reference inputs are DIMM0 `AY18/AY17` and DIMM1 `BB31/BB32`, nominally 100 MHz.
Offline implementation cannot verify the candidate memory pinout on this card.

### Onboard a different DIMM

Onboarding a new module requires a matching controller configuration and a new bitstream

1. Identify the module: Record the full part number, capacity,
   UDIMM/RDIMM/LRDIMM type, ranks, component density and width, module
   data/ECC width, voltage, address geometry and rank mirroring. Obtain the
   manufacturer's module/component datasheets and decoded SPD data where
   available. Do not use DIMMs.

2. Check the board wiring before changing settings: The existing candidate
   uses a single-rank x64 UDIMM pin map. Confirm the new module's required
   address, bank, chip-select, CKE, ODT, data, strobe and mask signals are routed
   on the XUP-VVP and supported by the DDR4 IP for this FPGA. Additional ranks,
   ECC lanes or registered/buffered modules require a board/IP compatibility
   review and may require a different design. Changing `DDR4_MemoryType` or
   `DDR4_DataWidth` alone does not add missing wiring. Keep package-pin locations
   tied to board routing, not the DIMM label. If constraints must change, make
   the change reproducible in the source scripts, `prepare.sh` overwrites its
   prepared XDC files on every invocation. Consult the DDR4 sections of
   [AMD PG150](https://docs.amd.com/r/en-US/pg150-ultrascale-memory-ip) for
   supported configurations and clocking.

3. Add accurate memory-part data: Add a row with a distinct `Part name` to
   `BLS4G4D240FSB.csv`, preserving the CSV schema and units. Populate geometry,
   rank/mirroring/mask fields and all timing values from the new module's
   specifications at the selected operating point, including refresh timings,
   CAS latency and CAS write latency. Do not just rename the existing row.
   If using a new CSV filename, update both its `import_files` statement and
   the `get_files -all *BLS4G4D240FSB.csv` lookup in `build.tcl`.

4. Update controller settings in `build.tcl`: Review these values in
   the `foreach dimm {0 1}` block:

   | Setting | Required action |
   | --- | --- |
   | `CONFIG.C0.DDR4_MemoryPart` | Use the new CSV row's exact `Part name` |
   | `CONFIG.C0.DDR4_CustomParts`, `DDR4_isCustom` | Keep the imported CSV selected and custom parts enabled |
   | `CONFIG.C0.DDR4_MemoryType`, `DDR4_DataWidth` | Match the supported module type and routed data width |
   | `CONFIG.C0.DDR4_TimePeriod` | Set memory clock period in ps for the chosen data rate |
   | `CONFIG.C0.DDR4_InputClockPeriod` | Match the board reference clock, changing DIMMs does not change this clock |
   | `CONFIG.C0.DDR4_CLKOUT0_DIVIDE` | Check the clock combination in Vivado's DDR4 IP configuration rather than guessing a divider |

   For example, the bundled `BLS4G4D240FSB-2133` row pairs with a memory period
   of `938` ps, while the current `-2400` row uses `833` ps. This illustrates
   selecting a row and operating point, it does not establish compatibility
   with another module. Use Vivado 2025.2's DDR4 IP customization to validate
   the complete settings and carry any additional generated properties back
   into `build.tcl`.

   The current loop applies the same settings to both controllers. Initially
   use the same DIMM type in both sockets, or populate only the selected
   socket. To support different types simultaneously, assign the matching
   settings per `$dimm` in that loop and include both part rows in the CSV.
   Each populated socket needs its own matching configuration even when it
   is unselected, both controllers attempt calibration after programming.

5. Match the address map to capacity: `build.tcl` currently gives each
   independent JTAG AXI master a 32-bit address bus and a `4G` region at zero.
   Review the controller's AXI address width and update both
   `CONFIG.M_AXI_ADDR_WIDTH` and `assign_bd_address -range` when required.
   For example, exposing an entire 8 GiB module requires a larger controller
   aperture, a master wider than 32 bits (64 bits is supported here), and an
   `8G` mapped range. A larger range does not create physical memory, and a
   smaller range cannot test the module's full capacity. Verify the generated
   block design's address map for each master.

6. Build a fresh image, program, and test
