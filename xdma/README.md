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

Remove an active XDMA PCIe function before programming, then rescan after
loading XDMA:

```sh
echo 1 | sudo tee /sys/bus/pci/devices/0000:06:00.0/remove
vivado -mode batch -source vivado/03-program.tcl
echo 1 | sudo tee /sys/class/pci_bus/0000:06/rescan
```

Use the PCIe address and bus for your host. Rescan after switching from a non-PCIe image back to XDMA.

## Test

Install [the XDMA reference driver and DMA tools](https://github.com/Xilinx/dma_ip_drivers/tree/master/XDMA).

Override `BDF`, `XDMA_INDEX`, `LINK_SPEED` and `LINK_WIDTH` for another host,
see `config.sh`. `DMA_BYTES` defaults to 524288 and `BENCH_COUNT` to 256.

Then, run `scripts/test.sh` with access to XDMA H2C/C2H channels to check PCIe
link status, verify a 512 KiB round-trip, and benchmark both directions.
