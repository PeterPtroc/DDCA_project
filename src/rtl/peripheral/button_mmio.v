`default_nettype none
module button_mmio #(
    parameter DEBOUNCE_BITS = 18
) (
    input wire clk,
    input wire rst,
    input wire [4:0] btn_async,
    input wire [15:0] sw_async,
    input wire event_read,
    output wire [4:0] button_state,
    output reg [4:0] button_event,
    output wire [15:0] switch_state,
    input wire [3:0] off,
    output reg [31:0] rdata
);
  wire [4:0] btn_sync;
  wire [15:0] sw_sync;
  wire [4:0] btn_level;
  wire [4:0] btn_pulse;

  input_sync #(.WIDTH(5)) sync_buttons (
      .clk(clk), .rst(rst), .async_in(btn_async), .sync_out(btn_sync)
  );
  input_sync #(.WIDTH(16)) sync_switches (
      .clk(clk), .rst(rst), .async_in(sw_async), .sync_out(sw_sync)
  );

  genvar i;
  generate
    for (i = 0; i < 5; i = i + 1) begin : gen_debounce
      button_debounce #(.COUNTER_BITS(DEBOUNCE_BITS)) db (
          .clk(clk), .rst(rst), .noisy(btn_sync[i]),
          .level(btn_level[i]), .pulse(btn_pulse[i])
      );
    end
  endgenerate

  assign button_state = btn_level;
  assign switch_state = sw_sync;

  always @* begin
    case (off)
      4'h0: rdata = {27'd0, button_state};
      4'h4: rdata = {27'd0, button_event};
      4'h8: rdata = {16'd0, switch_state};
      default: rdata = 32'd0;
    endcase
  end

  always @(posedge clk) begin
    if (rst) button_event <= 5'd0;
    else begin
      button_event <= (event_read ? 5'd0 : button_event) | btn_pulse;
    end
  end
endmodule
`default_nettype wire
