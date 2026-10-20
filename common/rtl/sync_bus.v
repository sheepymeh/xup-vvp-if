// Synchronize independent levels, multi-bit values need a separate coherency protocol
module sync_bus #(
    parameter WIDTH = 1,
    parameter STAGES = 3,
    parameter [WIDTH-1:0] INIT = 0
) (
    input wire clk,
    input wire [WIDTH-1:0] value,
    output wire [WIDTH-1:0] synced
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [WIDTH-1:0] sync_first = INIT;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [WIDTH-1:0] pipeline [0:STAGES-2];
    integer stage;
    integer index;
    initial begin
        for (index = 0; index < STAGES-1; index = index + 1)
            pipeline[index] = INIT;
    end
    always @(posedge clk) begin
        sync_first <= value;
        pipeline[0] <= sync_first;
        for (stage = 1; stage < STAGES-1; stage = stage + 1)
            pipeline[stage] <= pipeline[stage-1];
    end
    assign synced = pipeline[STAGES-2];
endmodule
