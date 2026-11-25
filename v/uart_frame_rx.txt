// ============================================================================
// uart_frame_rx.v - frame protocol parser
//
// Packet from the laptop:
//   0xAA 0x55, then 480*270 pixels in raster order, 3 bytes each (R, G, B)
//   = 2 + 388,800 bytes per image.
//
// Each complete pixel produces one write: we / waddr / wdata[23:0].
// frame_done pulses after the last pixel of a frame.
//
// Limitation: the sync is only looked for between frames. A dropped byte
// inside a frame shifts that frame until the next sync; the next upload
// realigns the picture. (See notes: a longer sync word, or an escape code,
// would allow mid-frame resync.)
// ============================================================================
module uart_frame_rx #(
    parameter integer PIXELS = 129600              // 480 x 270
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    output reg         we,
    output reg [16:0]  waddr,
    output reg [23:0]  wdata,
    output reg         frame_done
);

localparam [2:0] H_A    = 3'd0,   // waiting for 0xAA
                 H_B    = 3'd1,   // got 0xAA, waiting for 0x55
                 RX_R   = 3'd2,
                 RX_G   = 3'd3,
                 RX_B   = 3'd4;

reg [2:0]  st;
reg [16:0] pix_cnt;
reg [7:0]  r_byte, g_byte;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st         <= H_A;
        pix_cnt    <= 17'd0;
        r_byte     <= 8'd0;
        g_byte     <= 8'd0;
        we         <= 1'b0;
        waddr      <= 17'd0;
        wdata      <= 24'd0;
        frame_done <= 1'b0;
    end else begin
        we         <= 1'b0;
        frame_done <= 1'b0;

        if (rx_valid) begin
            case (st)
                H_A: begin
                    if (rx_data == 8'hAA)
                        st <= H_B;
                end

                H_B: begin
                    if (rx_data == 8'h55) begin
                        pix_cnt <= 17'd0;
                        st      <= RX_R;
                    end else if (rx_data == 8'hAA)
                        st <= H_B;               // repeated 0xAA, keep waiting
                    else
                        st <= H_A;
                end

                RX_R: begin
                    r_byte <= rx_data;
                    st     <= RX_G;
                end

                RX_G: begin
                    g_byte <= rx_data;
                    st     <= RX_B;
                end

                RX_B: begin
                    we    <= 1'b1;
                    waddr <= pix_cnt;
                    wdata <= {r_byte, g_byte, rx_data};
                    if (pix_cnt == PIXELS - 1) begin
                        frame_done <= 1'b1;
                        st         <= H_A;
                    end else begin
                        pix_cnt <= pix_cnt + 17'd1;
                        st      <= RX_R;
                    end
                end

                default: st <= H_A;
            endcase
        end
    end
end

endmodule
