`default_nettype none
// One read burst outstanding. Round-robin at burst boundaries; writes bypass it.
module axi_read_arbiter (
    input wire clk,rst,
    input wire [26:0] cpu_araddr,video_araddr,
    input wire [7:0] cpu_arlen,video_arlen,
    input wire [2:0] cpu_arsize,video_arsize,
    input wire [1:0] cpu_arburst,video_arburst,
    input wire cpu_arvalid,video_arvalid,
    output wire cpu_arready,video_arready,
    output wire [127:0] cpu_rdata,video_rdata,
    output wire [1:0] cpu_rresp,video_rresp,
    output wire cpu_rlast,video_rlast,cpu_rvalid,video_rvalid,
    input wire cpu_rready,video_rready,
    output reg [26:0] araddr,
    output reg [7:0] arlen,
    output reg [2:0] arsize,
    output reg [1:0] arburst,
    output wire arvalid,
    input wire arready,
    input wire [127:0] rdata,
    input wire [1:0] rresp,
    input wire rlast,rvalid,
    output wire rready
);
  localparam IDLE=0,ADDRESS=1,RESPONSE=2;
  reg [1:0] state;
  reg owner,last_owner;
  wire choose_video=video_arvalid && (!cpu_arvalid || !last_owner);
  assign arvalid=state==ADDRESS;
  assign cpu_arready=state==ADDRESS && !owner && arready;
  assign video_arready=state==ADDRESS && owner && arready;
  assign cpu_rdata=rdata;assign video_rdata=rdata;
  assign cpu_rresp=rresp;assign video_rresp=rresp;
  assign cpu_rlast=rlast;assign video_rlast=rlast;
  assign cpu_rvalid=state==RESPONSE && !owner && rvalid;
  assign video_rvalid=state==RESPONSE && owner && rvalid;
  assign rready=state==RESPONSE && (owner ? video_rready : cpu_rready);
  always @(posedge clk) begin
    if(rst) begin
      state<=IDLE;owner<=0;last_owner<=1;
      araddr<=0;arlen<=0;arsize<=4;arburst<=1;
    end else case(state)
      IDLE: if(cpu_arvalid || video_arvalid) begin
        owner<=choose_video;state<=ADDRESS;
        araddr<=choose_video ? video_araddr : cpu_araddr;
        arlen<=choose_video ? video_arlen : cpu_arlen;
        arsize<=choose_video ? video_arsize : cpu_arsize;
        arburst<=choose_video ? video_arburst : cpu_arburst;
      end
      ADDRESS: if(arready) state<=RESPONSE;
      RESPONSE: if(rvalid && rready && rlast) begin state<=IDLE;last_owner<=owner;end
      default:state<=IDLE;
    endcase
  end
endmodule
`default_nettype wire
