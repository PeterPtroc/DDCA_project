`default_nettype none
module uart_mmio #(
    parameter DIVIDER = 868
) (
    input wire clk,
    input wire rst,
    input wire rx,
    input wire we,
    input wire re,
    input wire [3:0] off,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output wire tx,
    output wire tx_ready,
    output wire rx_valid,
    output wire activity
);
  wire [7:0] received_data;
  wire received_strobe;
  reg [7:0] rx_data;
  reg rx_pending;
  wire tx_start = we && (off == 4'h0) && tx_ready;

  uart_tx #(.DIVIDER(DIVIDER)) tx_unit (
      .clk(clk), .rst(rst), .start(tx_start), .data(wdata[7:0]),
      .ready(tx_ready), .tx(tx)
  );
  uart_rx #(.DIVIDER(DIVIDER)) rx_unit (
      .clk(clk), .rst(rst), .rx(rx), .data(received_data),
      .valid(received_strobe)
  );

  assign rx_valid = rx_pending;
  assign activity = !tx_ready || rx_pending;

  always @* begin
    case (off)
      4'h4: rdata = {30'd0, rx_pending, tx_ready};
      4'h8: rdata = {24'd0, rx_data};
      default: rdata = 32'd0;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      rx_data <= 8'd0;
      rx_pending <= 1'b0;
    end else begin
      if (re && off == 4'h8) rx_pending <= 1'b0;
      if (received_strobe) begin
        rx_data <= received_data;
        rx_pending <= 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
