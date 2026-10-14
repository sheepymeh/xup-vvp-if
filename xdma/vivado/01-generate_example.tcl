set root [file join [file dirname [info script]] ..]
set build [file join $root build]
set_part xcvu13p-figd2104-2-e

create_ip \
    -name xdma \
    -vendor xilinx.com \
    -library ip \
    -module_name xdma_0 \
    -dir [file join $build ip]

set_property -dict [list \
    CONFIG.mode_selection Advanced \
    CONFIG.functional_mode DMA \
    CONFIG.device_port_type PCI_Express_Endpoint_device \
    CONFIG.xdma_axi_intf_mm AXI_Memory_Mapped \
    CONFIG.pl_link_cap_max_link_speed $::env(ENDPOINT_LINK_SPEED)_GT/s \
    CONFIG.pl_link_cap_max_link_width X$::env(ENDPOINT_LINK_WIDTH) \
    CONFIG.axi_data_width 512_bit \
    CONFIG.axisten_freq 250 \
    CONFIG.ref_clk_freq 100_MHz \
    CONFIG.sys_reset_polarity ACTIVE_LOW \
    CONFIG.en_gt_selection true \
    CONFIG.pcie_blk_locn X0Y1 \
    CONFIG.select_quad GTY_Quad_227 \
    CONFIG.vendor_id $::env(PCI_VENDOR_ID) \
    CONFIG.pf0_device_id $::env(PCI_DEVICE_ID) \
    CONFIG.xdma_rnum_chnl 1 \
    CONFIG.xdma_wnum_chnl 1 \
] [get_ips xdma_0]

generate_target all [get_ips xdma_0]
open_example_project -dir [file join $build example] -in_process [get_ips xdma_0]
close_project
