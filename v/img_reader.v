// Maps screen coordinates (x,y) to a ROM address for an IMG_W-wide image
// shown with integer upscaling by 2^SHIFT (SHIFT=2 -> 4x).
// Latency: addr is valid 1 clock after x,y (t1).
module img_reader #(
    parameter IMG_W = 480,
    parameter SHIFT = 2
)(
    input              clk,
    input      [10:0]  x,
    input      [10:0]  y,
    output reg [16:0]  addr
);

wire [10:0] xs = x >> SHIFT;     // source column
wire [10:0] ys = y >> SHIFT;     // source row

reg [16:0] row_base;             // address of the first pixel of the source row

always @(posedge clk) begin
    row_base <= ys * IMG_W;      // settles long before the line becomes active
    addr     <= row_base + xs;
end

endmodule