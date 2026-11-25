// Point-operation stage. One register stage (t2 -> t3).
// invert = 0 : pass-through
// invert = 1 : negative image, out = 255 - in on every channel (= bitwise NOT)
module pixel_proc (
    input              clk,
    input              invert,
    input      [23:0]  pix_in,     // {R[7:0], G[7:0], B[7:0]}
    output reg [23:0]  pix_out
);

always @(posedge clk)
    pix_out <= invert ? ~pix_in : pix_in;

endmodule