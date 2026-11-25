// ============================================================================
// image_path_top.v - laptop image -> UART -> frame buffer -> 1080p60 -> HDMI
//
// Replaces the vpg instance in golden_top. Outputs drive HDMI_TX_D[23:0],
// HDMI_TX_DE, HDMI_TX_HS, HDMI_TX_VS, and HDMI_TX_CLK_p = ~pclk (as now).
//
//   Clocks : clk50 = CLOCK0_50 (UART + write side)
//            pclk  = vpg_pclk  (148.5 MHz, 1080p60 pixel clock)
//   Scaling: stored 480x270 shown at 4x -> 1920x1080 (each source pixel is
//            a 4x4 block). Output is inverted (~RGB).
//   Timing : CEA-861 1080p60, active 1920x1080 at h 192..2111, v 41..1120.
//            Sync polarity matches vpg.v (low during sync), which is the
//            polarity that already works on your board.
//   Latency: 3 pclk cycles from counters to output pins (pipeline below).
// ============================================================================
module image_path_top #(
    parameter integer CLKS_PER_BIT = 434          // 50 MHz / 115200
)(
    input  wire        clk50,
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        uart_rx_pin,               // FPGA_UART_RX (PIN_L1)

    output reg  [7:0]  out_r,
    output reg  [7:0]  out_g,
    output reg  [7:0]  out_b,
    output reg         out_de,
    output reg         out_hs,
    output reg         out_vs
);

// ---------------------------------------------------------------------------
// UART receive side (clk50)
// ---------------------------------------------------------------------------
wire [7:0]  rx_byte;
wire        rx_valid;

uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
    .clk   (clk50),
    .rst_n (rst_n),
    .rx    (uart_rx_pin),
    .data  (rx_byte),
    .valid (rx_valid)
);

wire        we;
wire [16:0] waddr;
wire [23:0] wdata;
wire        frame_done;

uart_frame_rx u_frame_rx (
    .clk        (clk50),
    .rst_n      (rst_n),
    .rx_data    (rx_byte),
    .rx_valid   (rx_valid),
    .we         (we),
    .waddr      (waddr),
    .wdata      (wdata),
    .frame_done (frame_done)
);

// ---------------------------------------------------------------------------
// Frame buffer: write @ clk50, read @ pclk
// ---------------------------------------------------------------------------
wire [16:0] raddr;
wire [23:0] rdata;

frame_buffer u_frame_buffer (
    .wclk  (clk50),
    .we    (we),
    .waddr (waddr),
    .wdata (wdata),
    .rclk  (pclk),
    .raddr (raddr),
    .rdata (rdata)
);

// ---------------------------------------------------------------------------
// 1080p60 timing counters (pclk)
// ---------------------------------------------------------------------------
localparam [11:0] H_TOTAL   = 12'd2199;   // total - 1
localparam [11:0] V_TOTAL   = 12'd1124;   // total - 1
localparam [11:0] H_SYNC    = 12'd44;     // sync width (counts 0..43 low)
localparam [11:0] V_SYNC    = 12'd5;      // sync lines (0..4 low)
localparam [11:0] H_ACT0    = 12'd192;    // first active pixel
localparam [11:0] H_ACT1    = 12'd2111;   // last active pixel
localparam [11:0] V_ACT0    = 12'd41;     // first active line
localparam [11:0] V_ACT1    = 12'd1120;   // last active line

reg [11:0] h_cnt;
reg [11:0] v_cnt;

always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
        h_cnt <= 12'd0;
        v_cnt <= 12'd0;
    end else if (h_cnt == H_TOTAL) begin
        h_cnt <= 12'd0;
        v_cnt <= (v_cnt == V_TOTAL) ? 12'd0 : v_cnt + 12'd1;
    end else begin
        h_cnt <= h_cnt + 12'd1;
    end
end

// Combinational view of the current counter position stage 0
wire h_act = (h_cnt >= H_ACT0) && (h_cnt <= H_ACT1);
wire v_act = (v_cnt >= V_ACT0) && (v_cnt <= V_ACT1);
wire de_c  = h_act && v_act;
wire hs_c  = (h_cnt >= H_SYNC);
wire vs_c  = (v_cnt >= V_SYNC);

// 4x upscale addressing: source pixel = (x/4, y/4)
wire [10:0] x_rel = h_cnt - H_ACT0;       // 0..1919 when active
wire [10:0] y_rel = v_cnt - V_ACT0;       // 0..1079 when active
wire [8:0]  x4   = x_rel[10:2];           // 0..479
wire [8:0]  y4   = y_rel[10:2];           // 0..269
wire [16:0] row_base = {8'd0, y4} * 17'd480;
wire [16:0] addr_c   = de_c ? (row_base + {8'd0, x4}) : 17'd0;

// Stage 1: register the read address (RAM output is registered -> stage 2)
reg [16:0] raddr_r;
always @(posedge pclk) raddr_r <= addr_c;
assign raddr = raddr_r;

// Stage 2 and 3: delay control signals to line up with rdata
reg de_p1, de_p2;
reg hs_p1, hs_p2;
reg vs_p1, vs_p2;

always @(posedge pclk) begin
    de_p1 <= de_c;  de_p2 <= de_p1;
    hs_p1 <= hs_c;  hs_p2 <= hs_p1;
    vs_p1 <= vs_c;  vs_p2 <= vs_p1;
end

// Stage 3: invert and drive the output registers
always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
        out_r  <= 8'd0;
        out_g  <= 8'd0;
        out_b  <= 8'd0;
        out_de <= 1'b0;
        out_hs <= 1'b1;
        out_vs <= 1'b1;
    end else begin
        out_r  <= de_p2 ? ~rdata[23:16] : 8'd0;
        out_g  <= de_p2 ? ~rdata[15:8]  : 8'd0;
        out_b  <= de_p2 ? ~rdata[7:0]   : 8'd0;
        out_de <= de_p2;
        out_hs <= hs_p2;           // high outside sync, low during sync (as vpg.v)
        out_vs <= vs_p2;
    end
end

endmodule
