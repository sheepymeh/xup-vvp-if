set root [file join [file dirname [info script]] ..]
set build [file join $root build]
set example [file join $build example xdma_0_ex]
set rtl [file join $example imports]
source [file join $root .. common build.tcl]
set_part $::board::part

read_ip [file join $example xdma_0_ex.srcs sources_1 ip xdma_0 xdma_0.xci]
read_ip [file join $example xdma_0_ex.srcs sources_1 ip axi_bram_ctrl_1 axi_bram_ctrl_1.xci]
synth_ip [get_ips {xdma_0 axi_bram_ctrl_1}]

read_verilog -sv [file join $rtl xilinx_dma_pcie_ep.sv]
read_verilog [file join $rtl xdma_app.v]
read_xdc [file join $rtl xilinx_xdma_pcie_x0y1.xdc]
synth_design -top xilinx_dma_pcie_ep
write_checkpoint [file join $build synthesized.dcp]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint [file join $build routed.dcp]

build::check_implementation [file join $build reports]

write_bitstream -file [file join $build xdma.bit]
