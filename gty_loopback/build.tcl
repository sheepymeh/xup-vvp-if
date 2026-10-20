set root [file dirname [file normalize [info script]]]
set out [file join $root build]
file mkdir $out

set common [file join $root .. common]
source [file join $common build.tcl]
exec python3 [file join $root generate.py]
source [file join $out mapping.tcl]

create_project all_channels [file join $out project] -part $::board::part
set_property target_language Verilog [current_project]
add_files [list [file join $out top.v] [file join $root quad_control.v] \
    [file join $common rtl sync_bus.v]]
add_files -fileset constrs_1 [list [file join $out constraints.xdc] \
    [file join $common rtl sync_bus.xdc]]
set_property USED_IN_SYNTHESIS false [get_files sync_bus.xdc]
set_property top all_channels_top [get_filesets sources_1]

# One QPLL0 and four native PRBS lanes per quad, DRP writes are tied off in generated top.v
foreach quad $quads {
    lassign $quad number channels refclk
    set name gty_quad_$number
    set master [lindex $channels 0]
    set sources {}
    foreach channel $channels {
        lappend sources $channel $refclk
    }

    create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip -module_name $name
    set gt [get_ips $name]
    set_property -dict [list \
        CONFIG.GT_TYPE GTY CONFIG.CHANNEL_ENABLE $channels \
        CONFIG.TX_MASTER_CHANNEL $master CONFIG.RX_MASTER_CHANNEL $master \
        CONFIG.TX_PLL_TYPE QPLL0 CONFIG.RX_PLL_TYPE QPLL0 \
        CONFIG.TX_LINE_RATE 25.78125 CONFIG.RX_LINE_RATE 25.78125 \
        CONFIG.TX_REFCLK_FREQUENCY 322.265625 CONFIG.RX_REFCLK_FREQUENCY 322.265625 \
        CONFIG.TX_REFCLK_SOURCE $sources CONFIG.RX_REFCLK_SOURCE $sources \
        CONFIG.TX_USER_DATA_WIDTH 64 CONFIG.RX_USER_DATA_WIDTH 64 \
        CONFIG.TX_INT_DATA_WIDTH 64 CONFIG.RX_INT_DATA_WIDTH 64 \
        CONFIG.FREERUN_FREQUENCY 161.1328125 \
        CONFIG.LOCATE_TX_USER_CLOCKING CORE CONFIG.LOCATE_RX_USER_CLOCKING CORE \
        CONFIG.ENABLE_OPTIONAL_PORTS {
            loopback_in txprbssel_in rxprbssel_in
            rxprbscntreset_in rxprbserr_out rxprbslocked_out
            txprbsforceerr_in rxpolarity_in rxpmareset_in qpll0lock_out
            drpaddr_in drpclk_in drpdi_in drpen_in drprst_in drpwe_in
            drpdo_out drprdy_out
        } \
    ] $gt
    generate_target all $gt
    puts "CONFIGURED_QUAD=$number CHANNELS=$channels REFCLK=$sources"
}

build::create_vio prbs_vio $vio_inputs $vio_outputs
update_compile_order -fileset sources_1

foreach ip [get_ips] {
    create_ip_run $ip
}

build::disable_optional_reports
foreach ip [get_ips] {
    build::run ${ip}_synth_1
}
build::run synth_1
build::run impl_1 -to_step route_design
open_run impl_1

build::check_synchronizers
build::check_implementation [file join $out reports]

write_bitstream -force [file join $out all_channels.bit]
write_debug_probes -force [file join $out all_channels.ltx]
exec python3 [file join $root make_probes.py]
puts "BUILD_COMPLETE, FPGA_NOT_PROGRAMMED"
close_project
