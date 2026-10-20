// RX-domain faults persist between JTAG reads
module prbs_monitor (
    input wire clk, clear, measure,
    input wire [3:0] locked, errors,
    output reg [3:0] error_seen = 0,
    output reg [3:0] unlock_seen = 0
);
    always @(posedge clk) begin
        if (clear) begin
            error_seen <= 0;
            unlock_seen <= 0;
        end else if (measure) begin
            error_seen <= error_seen | errors;
            unlock_seen <= unlock_seen | ~locked;
        end
    end
endmodule

module quad_control (
    input wire clk, txclk, rxclk,

    // Lane status and shared reset/PLL completion
    input wire [3:0] powergood, txpma, rxpma, locked, prbserr,
    input wire txdone, rxdone, qplllock,

    output wire reset_all, reset_rx, reset_pma,
    output wire [2:0] loopback,
    output wire [3:0] count_reset, force_error, rxpolarity,

    // Four independent 16-bit DRP responses share one read address
    output wire [39:0] drpaddr,
    output wire [3:0] drpen,
    input wire [63:0] drpdo,
    input wire [3:0] drprdy
);
    wire count_reset_vio, clear_vio, measure_vio;
    wire [3:0] inject_toggle, inject_tx, polarity_vio;
    wire [9:0] address_vio;
    wire request_vio;
    wire count_reset_rx, clear_rx, measure_rx;
    sync_bus count_sync (.clk(rxclk), .value(count_reset_vio), .synced(count_reset_rx));
    sync_bus clear_sync (.clk(rxclk), .value(clear_vio), .synced(clear_rx));
    sync_bus measure_sync (.clk(rxclk), .value(measure_vio), .synced(measure_rx));
    sync_bus #(.WIDTH(4)) inject_sync (.clk(txclk), .value(inject_toggle), .synced(inject_tx));
    sync_bus #(.WIDTH(4)) polarity_sync (.clk(rxclk), .value(polarity_vio), .synced(rxpolarity));
    assign count_reset = {4{count_reset_rx}};

    // Toggle changes produce one TX-clock pulse per selected lane
    reg [3:0] inject_previous = 0;
    always @(posedge txclk) inject_previous <= inject_tx;
    assign force_error = inject_tx ^ inject_previous;

    // Capture faults before returning status to the control clock
    wire [3:0] error_seen_rx, unlock_seen_rx, error_seen, unlock_seen;
    prbs_monitor monitor (.clk(rxclk), .clear(clear_rx), .measure(measure_rx),
        .locked(locked), .errors(prbserr), .error_seen(error_seen_rx),
        .unlock_seen(unlock_seen_rx));
    sync_bus #(.WIDTH(4)) error_sync (.clk(clk), .value(error_seen_rx), .synced(error_seen));
    sync_bus #(.WIDTH(4)) unlock_sync (.clk(clk), .value(unlock_seen_rx), .synced(unlock_seen));

    // Lane readiness combines PMA completion, shared resets and QPLL lock
    wire [3:0] locked_sync, ready_sync;
    wire [14:0] status_sync;
    sync_bus #(.WIDTH(4)) lock_sync (.clk(clk), .value(locked), .synced(locked_sync));
    sync_bus #(.WIDTH(15)) ready_status_sync (.clk(clk),
        .value({powergood, txpma, rxpma, txdone, rxdone, qplllock}),
        .synced(status_sync));

    // PRBS lock is latched, detect a stopped RX monitor clock independently
    reg [7:0] rx_heartbeat = 0;
    always @(posedge rxclk) rx_heartbeat <= rx_heartbeat + 1'b1;
    wire heartbeat_sync;
    sync_bus heartbeat (.clk(clk), .value(rx_heartbeat[7]), .synced(heartbeat_sync));
    reg heartbeat_previous = 0;
    reg [15:0] rx_watchdog = 16'hffff;
    always @(posedge clk) begin
        heartbeat_previous <= heartbeat_sync;
        if (heartbeat_sync != heartbeat_previous) rx_watchdog <= 0;
        else if (!(&rx_watchdog)) rx_watchdog <= rx_watchdog + 1'b1;
    end

    assign ready_sync = status_sync[14:11] & status_sync[10:7] & status_sync[6:3]
        & {4{status_sync[2] & status_sync[1] & status_sync[0] & !(&rx_watchdog)}};

    // Preserve readiness loss even if it recovers before the next JTAG read
    reg [3:0] interrupted = 0;
    always @(posedge clk) begin
        if (clear_vio) interrupted <= 0;
        else if (measure_vio) interrupted <= interrupted | ~ready_sync;
    end

    // Broadcast one address, retain each lane response independently
    reg request_previous = 0;
    reg [3:0] enable = 0, busy = 0, done = 0, timeout = 0;
    reg [9:0] watchdog = 0;
    reg [63:0] read_data = 0;
    reg [9:0] held_address = 0;
    assign drpaddr = {4{held_address}};
    assign drpen = enable;
    integer lane;
    always @(posedge clk) begin
        request_previous <= request_vio;
        enable <= 0;
        if (|busy) begin
            if (&watchdog) begin
                timeout <= timeout | busy;
                busy <= 0;
            end else watchdog <= watchdog + 1'b1;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (busy[lane] && drprdy[lane]) begin
                    read_data[lane*16 +: 16] <= drpdo[lane*16 +: 16];
                    done[lane] <= 1'b1;
                    busy[lane] <= 1'b0;
                end
            end
        end else if (request_vio && !request_previous) begin
            held_address <= address_vio;
            enable <= 4'hf;
            busy <= 4'hf;
            done <= 0;
            timeout <= 0;
            watchdog <= 0;
        end
    end

    // Probe widths in generate.py, indices in hardware.tcl
    prbs_vio vio (
        .clk(clk),
        .probe_in0(ready_sync),
        .probe_in1(locked_sync),
        .probe_in2(error_seen),
        .probe_in3(unlock_seen | interrupted),
        .probe_in4(read_data),
        .probe_in5(done),
        .probe_in6(timeout),
        .probe_in7(busy),

        .probe_out0(reset_all),
        .probe_out1(reset_rx),
        .probe_out2(reset_pma),
        .probe_out3(loopback),
        .probe_out4(count_reset_vio),
        .probe_out5(clear_vio),
        .probe_out6(measure_vio),
        .probe_out7(inject_toggle),
        .probe_out8(address_vio),
        .probe_out9(request_vio),
        .probe_out10(polarity_vio));
endmodule
