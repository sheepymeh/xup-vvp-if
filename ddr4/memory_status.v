// Calibration remains readable when either DIMM UI clock is unavailable
module memory_status (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,
    input wire calibrated0,
    input wire calibrated1,
    input wire reset0,
    input wire reset1
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [3:0] status_meta = 4'b1100;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [3:0] status_sync = 4'b1100;

    always @(posedge clk) begin
        status_meta <= {reset1, reset0, calibrated1, calibrated0};
        status_sync <= status_meta;
    end

    // hardware.tcl reads bits 1:0 as calibration, bits 3:2 as UI reset
    ddr_status_vio vio (.clk(clk), .probe_in0(status_sync));
endmodule
