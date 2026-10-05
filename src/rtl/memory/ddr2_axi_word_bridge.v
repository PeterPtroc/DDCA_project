`default_nettype none
// One 32-bit request outstanding, completed only after the AXI response.
// The official MIG preset disables narrow bursts, so each transaction uses
// one aligned 128-bit beat; WSTRB preserves all adjacent bytes and words.
module ddr2_axi_word_bridge (
    input wire clk, rst,
    input wire valid, we,
    input wire [31:0] addr, wdata,
    input wire [3:0] wstrb,
    output wire ready,
    output reg [31:0] rdata,
    output reg error,
    output wire [26:0] axi_awaddr,
    output wire [7:0] axi_awlen,
    output wire [2:0] axi_awsize,
    output wire [1:0] axi_awburst,
    output wire axi_awvalid,
    input wire axi_awready,
    output wire [127:0] axi_wdata,
    output wire [15:0] axi_wstrb,
    output wire axi_wlast, axi_wvalid,
    input wire axi_wready,
    input wire [1:0] axi_bresp,
    input wire axi_bvalid,
    output wire axi_bready,
    output wire [26:0] axi_araddr,
    output wire [7:0] axi_arlen,
    output wire [2:0] axi_arsize,
    output wire [1:0] axi_arburst,
    output wire axi_arvalid,
    input wire axi_arready,
    input wire [127:0] axi_rdata,
    input wire [1:0] axi_rresp,
    input wire axi_rlast, axi_rvalid,
    output wire axi_rready
);
  localparam IDLE=0, WRITE=1, WRITE_RESPONSE=2, READ=3, READ_RESPONSE=4, DONE=5;
  reg [2:0] state = IDLE;
  reg [26:0] address;
  reg [1:0] word_lane;
  reg [127:0] data;
  reg [15:0] strobes;
  reg address_pending, data_pending;
  assign ready = state == DONE;
  assign axi_awaddr = address;
  assign axi_awlen = 0;
  assign axi_awsize = 3'd4;
  assign axi_awburst = 2'b01;
  assign axi_awvalid = state == WRITE && address_pending;
  assign axi_wdata = data;
  assign axi_wstrb = strobes;
  assign axi_wlast = 1'b1;
  assign axi_wvalid = state == WRITE && data_pending;
  assign axi_bready = state == WRITE_RESPONSE;
  assign axi_araddr = address;
  assign axi_arlen = 0;
  assign axi_arsize = 3'd4;
  assign axi_arburst = 2'b01;
  assign axi_arvalid = state == READ;
  assign axi_rready = state == READ_RESPONSE;
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      address <= 0; word_lane <= 0; data <= 0; strobes <= 0;
      address_pending <= 0; data_pending <= 0;
      rdata <= 0; error <= 0;
    end else begin
      case (state)
        IDLE: if (valid) begin
          address <= {addr[26:4], 4'b0000};
          word_lane <= addr[3:2];
          data <= {96'd0, wdata} << {addr[3:2], 5'b00000};
          strobes <= {12'd0, wstrb} << {addr[3:2], 2'b00};
          error <= 0;
          rdata <= 0;
          address_pending <= 1;
          data_pending <= 1;
          if (addr[31:27] != 5'b10000) begin
            error <= 1;
            state <= DONE;
          end else state <= we ? WRITE : READ;
        end
        WRITE: begin
          if (axi_awready) address_pending <= 0;
          if (axi_wready) data_pending <= 0;
          if ((!address_pending || axi_awready) && (!data_pending || axi_wready)) state <= WRITE_RESPONSE;
        end
        WRITE_RESPONSE: if (axi_bvalid) begin
          error <= axi_bresp != 0;
          state <= DONE;
        end
        READ: if (axi_arready) state <= READ_RESPONSE;
        READ_RESPONSE: if (axi_rvalid) begin
          rdata <= axi_rdata >> {word_lane, 5'b00000};
          error <= error || axi_rresp != 0 || !axi_rlast;
          // Drain a malformed multi-beat response before completing with an
          // error, keeping the shared AXI interface usable for later requests.
          if (axi_rlast) state <= DONE;
        end
        DONE: if (valid) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire
