// ============================================================================
// uart_rx.v - 8N1 UART receiver
// CLKS_PER_BIT = clk_freq / baud
//   50 MHz / 115200  = 434   (error 0.01%)
//   50 MHz / 921600  = 54    (error 0.46%)
//   50 MHz / 3125000 = 16    (exact)
// Input is synchronised with two flip-flops (rx comes from the FT2232H).
// ============================================================================
module uart_rx #(
    parameter integer CLKS_PER_BIT = 434
)(
    input  wire       clk,
    input  wire       rst_n,      // active-low, asynchronous
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid       // one-clock pulse when a byte has been received
);

localparam integer HALF = CLKS_PER_BIT / 2;

localparam [1:0] S_IDLE  = 2'd0,
                 S_START = 2'd1,
                 S_DATA  = 2'd2,
                 S_STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] clk_cnt;
reg [2:0]  bit_idx;
reg [7:0]  shift;
reg        rx_s1, rx_s2;

// Synchroniser
always @(posedge clk) begin
    rx_s1 <= rx;
    rx_s2 <= rx_s1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state   <= S_IDLE;
        clk_cnt <= 16'd0;
        bit_idx <= 3'd0;
        shift   <= 8'd0;
        data    <= 8'd0;
        valid   <= 1'b0;
    end else begin
        valid <= 1'b0;
        case (state)
            S_IDLE: begin
                clk_cnt <= 16'd0;
                bit_idx <= 3'd0;
                if (rx_s2 == 1'b0)          // falling edge = start bit
                    state <= S_START;
            end

            // Wait to the middle of the start bit and confirm it is still low
            S_START: begin
                if (clk_cnt == HALF[15:0]) begin
                    clk_cnt <= 16'd0;
                    if (rx_s2 == 1'b0)
                        state <= S_DATA;
                    else
                        state <= S_IDLE;     // glitch, not a real start bit
                end else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            // Sample each data bit in its middle, LSB first
            S_DATA: begin
                if (clk_cnt == HALF[15:0])
                    shift[bit_idx] <= rx_s2;
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 16'd0;
                    if (bit_idx == 3'd7) begin
                        bit_idx <= 3'd0;
                        state   <= S_STOP;
                    end else
                        bit_idx <= bit_idx + 3'd1;
                end else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            // Wait out the stop bit, then publish the byte
            S_STOP: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 16'd0;
                    data    <= shift;
                    valid   <= 1'b1;
                    state   <= S_IDLE;
                end else
                    clk_cnt <= clk_cnt + 16'd1;
            end
        endcase
    end
end

endmodule
