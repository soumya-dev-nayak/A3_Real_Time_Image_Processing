module golden_top (
    input              CLOCK0_50,
    input      [1:0]   KEY,            // active-low
    input      [1:0]   SW,
    output     [3:0]   LED,            // active-low

    input              FPGA_UART_RX,   // NEW: serial data from the PC (via FT2232H)

    inout              HDMI_I2C_SCL,
    inout              HDMI_I2C_SDA,
    output             HDMI_TX_HS,
    output             HDMI_TX_VS,
    output     [23:0]  HDMI_TX_D,
    output             HDMI_TX_DE,
    output             HDMI_TX_CLK_p,
    output             HDMI_ISEL,
    output             HDMI_PD_n
);

//=======================================================
//  Reset / I2C configuration of the TFP410 (same as Terasic)
//=======================================================
wire i2c_rst_n;
RESET_DELY u_RESET_DELY (
    .BUTTON (KEY[1]),
    .OSC_50 (CLOCK0_50),
    .RESET_n(i2c_rst_n)
);

wire ninit_done;
reset_release u_reset_release (
    .ninit_done(ninit_done)
);
wire reset_n = ~ninit_done;

assign HDMI_ISEL = reset_n;      // 1 = I2C mode
assign HDMI_PD_n = 1'b1;

wire [15:0] VEN_ID, DEV_ID;
wire        tfp_ready;

TFP410_I2C u_TFP410_I2C (
    .clk50       (CLOCK0_50),
    .reset_n     (i2c_rst_n),
    .i2c_clk     (HDMI_I2C_SCL),
    .i2c_dat     (HDMI_I2C_SDA),
    .SLAVE_ADDR_R(8'h78),
    .VEN_ID      (VEN_ID),
    .DEV_ID      (DEV_ID),
    .READY       (tfp_ready)
);

//=======================================================
//  Pixel clock + video reset
//=======================================================
wire pclk, pll_locked;
V_PLL u_V_PLL (
    .refclk  (CLOCK0_50),
    .rst     (1'b0),
    .outclk_0(pclk),             // 148.5 MHz
    .locked  (pll_locked)
);

// async assert, synchronous release, in the pixel-clock domain
wire       video_arst_n = pll_locked & reset_n;
reg  [2:0] rst_pipe;

always @(posedge pclk or negedge video_arst_n)
    if (!video_arst_n) rst_pipe <= 3'b000;
    else               rst_pipe <= {rst_pipe[1:0], 1'b1};
wire video_rst_n = rst_pipe[2];

// SW[0] is asynchronous to pclk -> 2-flop synchronizer
reg [1:0] sw_sync;
always @(posedge pclk) sw_sync <= {sw_sync[0], SW[0]};
wire invert = sw_sync[1];

//=======================================================
//  NEW: UART image receiver (50 MHz domain)
//  Packet: 0xAA 0x55 + 480*270 pixels, R,G,B bytes, raster order
//  115200 baud -> CLKS_PER_BIT = 50e6/115200 = 434
//  (921600 -> 54, 3125000 -> 16; change here and in the PC program)
//=======================================================
// async assert, synchronous release in the 50 MHz domain.
// Pressing KEY[0] resets the receiver if it ever loses its place.
wire       uart_arst_n = reset_n & KEY[0];
reg  [2:0] rst50_pipe;

always @(posedge CLOCK0_50 or negedge uart_arst_n)
    if (!uart_arst_n) rst50_pipe <= 3'b000;
    else              rst50_pipe <= {rst50_pipe[1:0], 1'b1};
wire uart_rst_n = rst50_pipe[2];

wire [7:0] rx_byte;
wire       rx_valid;
uart_rx #(.CLKS_PER_BIT(434)) u_uart_rx (
    .clk  (CLOCK0_50),
    .rst_n(uart_rst_n),
    .rx   (FPGA_UART_RX),
    .data (rx_byte),
    .valid(rx_valid)
);

wire        fb_we;
wire [16:0] fb_waddr;
wire [23:0] fb_wdata;
uart_frame_rx u_frame_rx (
    .clk       (CLOCK0_50),
    .rst_n     (uart_rst_n),
    .rx_data   (rx_byte),
    .rx_valid  (rx_valid),
    .we        (fb_we),
    .waddr     (fb_waddr),
    .wdata     (fb_wdata),
    .frame_done()
);

// Activity LED helper: lights while the UART line is toggling (stretched ~84 ms)
reg [1:0]  rx_sync;
reg [21:0] rx_stretch;
always @(posedge CLOCK0_50) begin
    rx_sync <= {rx_sync[0], FPGA_UART_RX};
    if (!rx_sync[1])             rx_stretch <= 22'h3FFFFF;
    else if (rx_stretch != 22'd0) rx_stretch <= rx_stretch - 22'd1;
end
wire rx_activity = (rx_stretch != 22'd0);

//=======================================================
//  Video pipeline  (unchanged, timing already proven on the board)
//  t0 video_timing -> t1 img_reader -> t2 frame_buffer -> t3 pixel_proc
//=======================================================
wire        t0_de, t0_hs, t0_vs;
wire [10:0] t0_x, t0_y;
video_timing u_timing (
    .clk  (pclk),
    .rst_n(video_rst_n),
    .de   (t0_de),
    .hs   (t0_hs),
    .vs   (t0_vs),
    .x    (t0_x),
    .y    (t0_y)
);

wire [16:0] t1_addr;
img_reader #(.IMG_W(480), .SHIFT(2)) u_reader (
    .clk (pclk),
    .x   (t0_x),
    .y   (t0_y),
    .addr(t1_addr)
);

// CHANGED: image_rom (read-only) -> frame_buffer (written by UART @50 MHz,
// read by the video pipeline @148.5 MHz). Same 1-clock read latency as the ROM.
wire [23:0] t2_pix;
frame_buffer u_frame_buffer (
    .wclk (CLOCK0_50),
    .we   (fb_we),
    .waddr(fb_waddr),
    .wdata(fb_wdata),
    .rclk (pclk),
    .raddr(t1_addr),
    .rdata(t2_pix)
);

wire [23:0] t3_pix;
pixel_proc u_proc (
    .clk    (pclk),
    .invert (invert),
    .pix_in (t2_pix),
    .pix_out(t3_pix)
);

// sync signals take the same 3 clocks as the pixel data
wire t3_de, t3_hs, t3_vs;
sync_delay #(.N(3), .W(3)) u_sync_delay (
    .clk (pclk),
    .din ({t0_de, t0_hs, t0_vs}),
    .dout({t3_de, t3_hs, t3_vs})
);

assign HDMI_TX_D     = t3_pix;
assign HDMI_TX_DE    = t3_de;
assign HDMI_TX_HS    = t3_hs;
assign HDMI_TX_VS    = t3_vs;
assign HDMI_TX_CLK_p = ~pclk;      // same as Terasic: TFP410 samples mid-data

//=======================================================
//  LEDs (active-low): [3]=UART activity, [2]=heartbeat, [1]=PLL locked, [0]=TFP410 ready
//  (CHANGED: LED[3] was "invert on"; SW[0] still inverts, you can see it on screen)
//=======================================================
wire heartbeat;
CLOCKMEM u_heartbeat (
    .reset   (1'b0),
    .CLK     (pclk),
    .CLK_FREQ(32'd148_500_000),
    .CK_1HZ  (heartbeat)
);

assign LED = ~{rx_activity, heartbeat, pll_locked, tfp_ready};

endmodule