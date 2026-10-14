set root [file join [file dirname [info script]] ..]
set build [file join $root build]
set example [file join $build example xdma_0_ex]
set rtl [file join $example imports]
set_part xcvu13p-figd2104-2-e

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

set reports [file join $build reports]
file mkdir $reports
report_route_status -file [file join $reports route.rpt]
report_drc -file [file join $reports drc.rpt]
report_timing_summary -file [file join $reports timing.rpt]
foreach kind {setup hold} {
    set paths [get_timing_paths -$kind -max_paths 1]
    if {[llength $paths] == 0} {error "No $kind timing paths"}
    set slack [get_property SLACK [lindex $paths 0]]
    if {$slack < 0} {error "$kind timing failed: slack=$slack"}
    puts "TIMING $kind worst slack: $slack ns"
}

write_bitstream -file [file join $build xdma.bit]
