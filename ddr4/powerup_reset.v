// One device-wide startup/DCI sequence, independent of either DIMM clock
module powerup_reset (
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 sys_rst RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire sys_rst,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 monitor_clk CLK" *)
    output wire monitor_clk,
    output wire [3:0] startup_status
);
    wire cfgmclk;
    wire eos;
    wire dci_locked;
    wire dci_reset;

    // CFGMCLK is an oscillator, these counts do not specify a precise delay
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg eos_meta = 1'b0;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg eos_sync = 1'b0;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] locked_sync = 2'b00;
    reg [21:0] count = 22'b0;
    reg sys_rst_q = 1'b1;

    STARTUPE3 #(.PROG_USR("FALSE"), .SIM_CCLK_FREQ(0.0)) startup_inst (
        .CFGCLK(), .CFGMCLK(cfgmclk), .DI(), .EOS(eos), .PREQ(),
        .DO(4'b0000), .DTS(4'b1111), .FCSBO(1'b1), .FCSBTS(1'b1),
        .GSR(1'b0), .GTS(1'b0), .KEYCLEARB(1'b1), .PACK(1'b0),
        .USRCCLKO(1'b0), .USRCCLKTS(1'b1),
        .USRDONEO(1'b1), .USRDONETS(1'b1)
    );
    BUFG cfg_buf (.I(cfgmclk), .O(monitor_clk));

    // Bank 65 requires a DCI reset pulse after end of startup
    assign dci_reset = !eos_sync || (count < 22'd4096);
    DCIRESET dci_reset_inst (.LOCKED(dci_locked), .RST(dci_reset));

    always @(posedge monitor_clk) begin
        eos_meta <= eos;
        eos_sync <= eos_meta;
        if (!eos_sync) begin
            count <= 22'b0;
            locked_sync <= 2'b00;
            sys_rst_q <= 1'b1;
        end else begin
            if (!(&count)) begin
                count <= count + 1'b1;
            end
            locked_sync <= {locked_sync[0], dci_locked};
            sys_rst_q <= !(&count) || !locked_sync[1];
        end
    end

    // Registered output avoids a combinational path into controller reset
    assign sys_rst = sys_rst_q;
    assign startup_status = {sys_rst_q, dci_reset, locked_sync[1], eos_sync};
endmodule
