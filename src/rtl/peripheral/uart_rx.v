`default_nettype none
module uart_rx #(
    parameter DIVIDER = 868
) (
    input wire clk,
    input wire rst,
    input wire rx,
    output reg [7:0] data,
    output reg valid
);
  (* ASYNC_REG = "TRUE" *) reg rx_meta;
  reg rx_sync;
  reg busy;
  reg [15:0] divcnt;
  reg [3:0] bitcnt;
  reg [7:0] shreg;

  always @(posedge clk) begin
    if (rst) begin
      rx_meta <= 1'b1;
      rx_sync <= 1'b1;
      busy <= 1'b0;
      divcnt <= 16'd0;
      bitcnt <= 4'd0;
      shreg <= 8'd0;
      data <= 8'd0;
      valid <= 1'b0;
    end else begin
      rx_meta <= rx;
      rx_sync <= rx_meta;
      valid <= 1'b0;
      if (!busy) begin
        if (!rx_sync) begin
          busy <= 1'b1;
          divcnt <= DIVIDER + (DIVIDER >> 1) - 1;
          bitcnt <= 4'd0;
        end
      end else if (divcnt != 0) begin
        divcnt <= divcnt - 1'b1;
      end else if (bitcnt < 8) begin
        shreg[bitcnt] <= rx_sync;
        bitcnt <= bitcnt + 1'b1;
        divcnt <= DIVIDER - 1;
      end else begin
        busy <= 1'b0;
        if (rx_sync) begin
          data <= shreg;
          valid <= 1'b1;
        end
      end
    end
  end
endmodule
`default_nettype wire
