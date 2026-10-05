`default_nettype none
module uart_mmio #(
    parameter DIVIDER = 868,
    parameter RX_FIFO_DEPTH = 1024
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
  localparam RX_PTR_BITS = (RX_FIFO_DEPTH > 1) ? $clog2(RX_FIFO_DEPTH) : 1;
  reg [7:0] rx_fifo [0:RX_FIFO_DEPTH-1];
  reg [RX_PTR_BITS-1:0] rx_read_ptr, rx_write_ptr;
  reg [RX_PTR_BITS:0] rx_count;
  reg rx_overflow;
  wire rx_pending = (rx_count != 0);
  wire rx_full = (rx_count == RX_FIFO_DEPTH);
  wire rx_pop = re && (off == 4'h8) && rx_pending;
  wire rx_push = received_strobe && (!rx_full || rx_pop);
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
      4'h4: rdata = {28'd0, rx_full, rx_overflow, rx_pending, tx_ready};
      4'h8: rdata = rx_pending ? {24'd0, rx_fifo[rx_read_ptr]} : 32'd0;
      default: rdata = 32'd0;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      rx_read_ptr <= 0;
      rx_write_ptr <= 0;
      rx_count <= 0;
      rx_overflow <= 1'b0;
    end else begin
      if (we && off == 4'h4 && wdata[2]) rx_overflow <= 1'b0;
      if (received_strobe && !rx_push) rx_overflow <= 1'b1;
      if (rx_pop) begin
        rx_read_ptr <= (rx_read_ptr == RX_FIFO_DEPTH-1) ? 0 : rx_read_ptr + 1'b1;
      end
      if (rx_push) begin
        rx_fifo[rx_write_ptr] <= received_data;
        rx_write_ptr <= (rx_write_ptr == RX_FIFO_DEPTH-1) ? 0 : rx_write_ptr + 1'b1;
      end
      case ({rx_push, rx_pop})
        2'b10: rx_count <= rx_count + 1'b1;
        2'b01: rx_count <= rx_count - 1'b1;
        default: ;
      endcase
    end
  end
endmodule
`default_nettype wire
