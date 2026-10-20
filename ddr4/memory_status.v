// Calibration remains readable when either DIMM UI clock is unavailable
module memory_status (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,
    input wire calibrated0,
    input wire calibrated1,
    input wire reset0,
    input wire reset1,
    input wire [3:0] startup_status,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ui_clk0 CLK" *)
    input wire ui_clk0,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ui_clk1 CLK" *)
    input wire ui_clk1
);
    wire [3:0] status_sync;
    sync_bus #(.WIDTH(4), .STAGES(2), .INIT(4'b1100)) status_cdc (
        .clk(clk), .value({reset1, reset0, calibrated1, calibrated0}),
        .synced(status_sync)
    );

    // Cross only divided clock levels, counters remain in monitor clock domain
    reg [19:0] divider0 = 0;
    reg [19:0] divider1 = 0;
    always @(posedge ui_clk0) divider0 <= divider0 + 1'b1;
    always @(posedge ui_clk1) divider1 <= divider1 + 1'b1;

    wire [1:0] ticks;
    sync_bus #(.WIDTH(2), .STAGES(2)) clock_cdc (
        .clk(clk), .value({divider1[19], divider0[19]}), .synced(ticks)
    );
    reg [1:0] previous_ticks = 0;
    reg [31:0] ui_edges0 = 0;
    reg [31:0] ui_edges1 = 0;
    reg [31:0] monitor_cycles = 0;
    always @(posedge clk) begin
        previous_ticks <= ticks;
        if (ticks[0] && !previous_ticks[0]) ui_edges0 <= ui_edges0 + 1'b1;
        if (ticks[1] && !previous_ticks[1]) ui_edges1 <= ui_edges1 + 1'b1;
        monitor_cycles <= monitor_cycles + 1'b1;
    end

    // probe_in0 retains its calibration/reset bit layout
    ddr_status_vio vio (
        .clk(clk), .probe_in0(status_sync), .probe_in1(startup_status),
        .probe_in2(ui_edges0), .probe_in3(ui_edges1), .probe_in4(monitor_cycles)
    );
endmodule
