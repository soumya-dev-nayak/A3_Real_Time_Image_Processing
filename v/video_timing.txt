// 1080p60 timing generator (148.5 MHz pixel clock)
// All outputs are registered together, so de/hs/vs/x/y are aligned (call this time t0).
// x,y are the active-area coordinates and are only meaningful while de = 1.
module video_timing #(
    parameter H_ACT = 1920, H_FP = 88, H_SYNC = 44, H_BP = 148,
    parameter V_ACT = 1080, V_FP = 4,  V_SYNC = 5,  V_BP = 36,
    parameter HS_ACTIVE = 0,      // 0 = sync pulse is low (idle high), 1 = pulse is high
    parameter VS_ACTIVE = 0
)(
    input              clk,       // pixel clock
    input              rst_n,     // synchronous, active-low
    output reg         de,
    output reg         hs,
    output reg         vs,
    output reg [10:0]  x,
    output reg [10:0]  y
);

localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;   // 2200
localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;   // 1125
localparam H_START = H_SYNC + H_BP;                  // first active column
localparam V_START = V_SYNC + V_BP;                  // first active line

reg [11:0] h_cnt;
reg [10:0] v_cnt;

wire h_last = (h_cnt == H_TOTAL - 1);
wire v_last = (v_cnt == V_TOTAL - 1);

// Line layout: [ sync | back porch | active | front porch ]
wire h_act    = (h_cnt >= H_START) && (h_cnt < H_START + H_ACT);
wire v_act    = (v_cnt >= V_START) && (v_cnt < V_START + V_ACT);
wire hs_pulse = (h_cnt < H_SYNC);
wire vs_pulse = (v_cnt < V_SYNC);

always @(posedge clk) begin
    if (!rst_n) begin
        h_cnt <= 12'd0;
        v_cnt <= 11'd0;
        de <= 1'b0;
        hs <= ~HS_ACTIVE[0];
        vs <= ~VS_ACTIVE[0];
        x  <= 11'd0;
        y  <= 11'd0;
    end else begin
        // counters
        if (h_last) begin
            h_cnt <= 12'd0;
            v_cnt <= v_last ? 11'd0 : v_cnt + 11'd1;
        end else
            h_cnt <= h_cnt + 12'd1;

        // registered outputs (all one stage behind the counters, together)
        de <= h_act & v_act;
        hs <= HS_ACTIVE ? hs_pulse : ~hs_pulse;
        vs <= VS_ACTIVE ? vs_pulse : ~vs_pulse;
        x  <= h_cnt - H_START;
        y  <= v_cnt - V_START;
    end
end

endmodule