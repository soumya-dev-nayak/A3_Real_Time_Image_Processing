// sync_delay.v - delays a W-bit bus by exactly N clock cycles.
// Used to line up de/hs/vs with the pixel data (3 clocks: reader, RAM, pixel_proc).
module sync_delay #(
    parameter N = 3,          // delay in clock cycles (>= 1)
    parameter W = 3           // bus width
)(
    input  wire           clk,
    input  wire [W-1:0]   din,
    output wire [W-1:0]   dout
);

reg [W-1:0] pipe [0:N-1];
integer i;

always @(posedge clk) begin
    pipe[0] <= din;
    for (i = 1; i < N; i = i + 1)
        pipe[i] <= pipe[i-1];
end

assign dout = pipe[N-1];

endmodule
