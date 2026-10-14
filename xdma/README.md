# XUP-VVP XDMA bring-up

Build and test XDMA on Gen3 x16 on a BittWare XUP-VVP (`xcvu13p-figd2104-2-e`).
Using AMD's AXI-MM BRAM example with one H2C and one C2H channel.
The host test defaults to a negotiated Gen2 x4 link.

Build and test configs are in `config.sh` or the top of `scripts/test.sh`.
XDMA IP configs are in `vivado/01-generate_example.tcl`.

## Build

Install Vivado 2025.2 and [the XDMA reference driver](https://github.com/Xilinx/dma_ip_drivers/tree/master/XDMA/linux-kernel).

Then, run `scripts/build.sh` to generate `build/xdma.bit`.
The build applies a XUP-VVP reference-clock pin fix and two missing wire declarations in `vivado/xup-vvp.patch`.
Delete or move `build/` to start a fresh build.

## Program

Only one Digilent USB JTAG target should be attached to the host.

Remove the PCIe function before programming, program, then rescan its bus:

```sh
echo 1 | sudo tee /sys/bus/pci/devices/0000:06:00.0/remove
vivado -mode batch -source vivado/03-program.tcl
echo 1 | sudo tee /sys/class/pci_bus/0000:06/rescan
```

Use the PCIe address and bus for your host.

## Test

When moving the card to another host, edit `BDF` (run `lspci -Dnn -d 10ee:9031`),
`XDMA_INDEX` (the N in `/dev/xdmaN_*`),
and the expected `LINK_SPEED` / `LINK_WIDTH` in `config.sh`.

Then, run `scripts/test.sh` as root (for access to XDMA H2C/C2H channels) to check PCIe link status,
then attempt and verify a 1KB round-trip.
