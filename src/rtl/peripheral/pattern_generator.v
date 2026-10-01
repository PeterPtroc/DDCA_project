`default_nettype none
module pattern_generator (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [4:0] off,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output wire enabled,
    output wire [7:0] pattern_out
);
  reg [7:0] enable_mask;
  reg [7:0] mode;
  reg [31:0] period;
  reg [31:0] high;
  reg [7:0] data;
  reg [31:0] count;
  reg toggle_state;
  wire [31:0] safe_period = (period < 2) ? 32'd2 : period;
  wire [31:0] high_clamped = (high > safe_period) ? safe_period : high;
  wire pwm = count < high_clamped;
  wire divider = count < (safe_period >> 1);
  wire [7:0] generated = {data[7:3], toggle_state, divider, pwm};

  assign enabled = |enable_mask;
  assign pattern_out = (generated & enable_mask) | (data & ~enable_mask);

  always @* begin
    case (off)
      5'h00: rdata = {24'd0, enable_mask};
      5'h04: rdata = {24'd0, mode};
      5'h08: rdata = period;
      5'h0c: rdata = high;
      5'h10: rdata = {24'd0, data};
      default: rdata = 32'd0;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      enable_mask <= 8'd0;
      mode <= 8'h07;
      period <= 32'd1000;
      high <= 32'd300;
      data <= 8'd0;
      count <= 32'd0;
      toggle_state <= 1'b0;
    end else begin
      if (we)
        case (off)
          5'h00: enable_mask <= wdata[7:0];
          5'h04: mode <= wdata[7:0];
          5'h08: period <= wdata;
          5'h0c: high <= wdata;
          5'h10: begin
            data <= wdata[7:0];
            if (mode[2]) toggle_state <= ~toggle_state;
          end
          default: ;
        endcase
      if (!enabled) begin
        count <= 32'd0;
      end else if (count >= safe_period - 1'b1) begin
        count <= 32'd0;
        if (mode[2]) toggle_state <= ~toggle_state;
      end else begin
        count <= count + 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
