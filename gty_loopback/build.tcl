# ---- Project and board mapping ----
set root [file dirname [file normalize [info script]]]
set out [file join $root build]
file mkdir $out

# Fixed GT sites and reference input for each four-lane core
set quads {
    {233 {X1Y52 X1Y53 X1Y54 X1Y55} clk1}
    {232 {X1Y48 X1Y49 X1Y50 X1Y51} clk1}
    {229 {X1Y36 X1Y37 X1Y38 X1Y39} clk1}
    {228 {X1Y32 X1Y33 X1Y34 X1Y35} clk1}
    {129 {X0Y36 X0Y37 X0Y38 X0Y39} clk0}
    {133 {X0Y52 X0Y53 X0Y54 X0Y55} clk0}
    {120 {X0Y0 X0Y1 X0Y2 X0Y3} clk0}
    {121 {X0Y4 X0Y5 X0Y6 X0Y7} clk0}
}

create_project all_channels [file join $out project] -part xcvu13p-figd2104-2-e
set_property target_language Verilog [current_project]
add_files [list [file join $root top.v] [file join $root quad_control.v]]
add_files -fileset constrs_1 [file join $root constraints.xdc]
set_property top all_channels_top [get_filesets sources_1]

# ---- GT Wizard IP ----
# One QPLL0 and four native PRBS lanes per quad, DRP writes are tied off in top.v
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

# ---- VIO IP ----
# Probe widths must match quad_control.v and hardware.tcl indices
create_ip -name vio -vendor xilinx.com -library ip -module_name prbs_vio
set vio [get_ips prbs_vio]
set params [list CONFIG.C_NUM_PROBE_IN 8 CONFIG.C_NUM_PROBE_OUT 11]
foreach index {0 1 2 3 5 6 7} {
    lappend params CONFIG.C_PROBE_IN${index}_WIDTH 4
}
lappend params CONFIG.C_PROBE_IN4_WIDTH 64

foreach index {0 1 2 4 5 6 9} {
    lappend params CONFIG.C_PROBE_OUT${index}_WIDTH 1
}
lappend params CONFIG.C_PROBE_OUT7_WIDTH 4 CONFIG.C_PROBE_OUT10_WIDTH 4
lappend params CONFIG.C_PROBE_OUT3_WIDTH 3 CONFIG.C_PROBE_OUT8_WIDTH 10
set_property -dict $params $vio
generate_target all $vio
update_compile_order -fileset sources_1

# ---- Sequential synthesis and implementation ----
foreach ip [get_ips] {
    create_ip_run $ip
}

# Suppress optional reports, preserve build and bitstream checks
foreach run [get_runs] {
    foreach report [get_report_configs -of_objects $run] {
        set_property IS_ENABLED false $report
    }
}

# Keep IP syntheses sequential on this memory-constrained host
foreach ip [get_ips] {
    set run ${ip}_synth_1
    launch_runs $run -jobs 1
    wait_on_run $run
    set status [get_property STATUS [get_runs $run]]
    if {![string match "*Complete*" $status]} {
        error "$run failed: $status"
    }
}

# Top synthesis consumes the completed IP checkpoints
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "Top synthesis failed"
}

launch_runs impl_1 -to_step route_design -jobs 1
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation failed"
}
open_run impl_1

# ---- Timing gate and programming artifacts ----
# Reject timing failures before emitting the programmable image
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} {
    error "Missing timing paths"
}
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {
    error "Timing requirements not met"
}

write_bitstream -force [file join $out all_channels.bit]
write_debug_probes -force [file join $out all_channels.ltx]
exec python3 [file join $root make_probes.py]
puts "BUILD_COMPLETE, FPGA_NOT_PROGRAMMED"
close_project
