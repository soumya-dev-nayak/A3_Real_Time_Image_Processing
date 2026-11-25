// ============================================================================
// frame_buffer.v - simple dual-port RAM, separate write and read clocks
//   Write: wclk (50 MHz, UART side)
//   Read : rclk (148.5 MHz, HDMI pixel side)
//   480 x 270 x 24 bit = 3.1 Mbit  -> fits in the A3's 6.89 Mbit M20K
//
// Initial contents come from image.mif (24-bit wide, 129600 words) so the
// board still shows the stored picture after power-up. Remove the attribute
// if your .mif does not match this width/depth.
// ============================================================================
module frame_buffer (
    input  wire        wclk,
    input  wire        we,
    input  wire [16:0] waddr,
    input  wire [23:0] wdata,

    input  wire        rclk,
    input  wire [16:0] raddr,
    output reg  [23:0] rdata
);

(* ram_style = "M20K", ram_init_file = "C:/QUARTUS_PRIME_PROJECTS/A3_Real_Time_Image_Processing/mif/image.mif" *)
reg [23:0] mem [0:129599];

always @(posedge wclk) begin
    if (we)
        mem[waddr] <= wdata;
end

always @(posedge rclk) begin
    rdata <= mem[raddr];
end

endmodule
