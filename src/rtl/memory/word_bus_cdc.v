`default_nettype none
// Bundled-data, one-outstanding asynchronous mailbox. Payload is held until
// the synchronized completion returns. Both resets must assert together on
// calibration loss; each domain must release reset synchronously to its clock.
module word_bus_cdc (
    input wire source_clk, source_rst,
    input wire source_valid, source_we,
    input wire [31:0] source_addr, source_wdata,
    input wire [3:0] source_wstrb,
    output wire source_ready,
    output reg [31:0] source_rdata,
    output reg source_error,
    input wire target_clk, target_rst,
    output reg target_valid, target_we,
    output reg [31:0] target_addr, target_wdata,
    output reg [3:0] target_wstrb,
    input wire target_ready,
    input wire [31:0] target_rdata,
    input wire target_error
);
  localparam IDLE=0, WAIT=1, DONE=2;
  reg [1:0] source_state;
  reg request_toggle, completion_toggle;
  reg payload_we;
  reg [31:0] payload_addr, payload_data, response_data;
  reg [3:0] payload_strobes;
  reg response_error;
  (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync, completion_sync;
  assign source_ready=source_state==DONE;
  always @(posedge source_clk or posedge source_rst) begin
    if(source_rst) begin
      source_state<=IDLE; request_toggle<=0; completion_sync<=0;
      payload_we<=0; payload_addr<=0; payload_data<=0; payload_strobes<=0;
      source_rdata<=0; source_error<=0;
    end else begin
      completion_sync<={completion_sync[0],completion_toggle};
      case(source_state)
        IDLE: if(source_valid) begin
          payload_we<=source_we; payload_addr<=source_addr;
          payload_data<=source_wdata; payload_strobes<=source_wstrb;
          request_toggle<=!request_toggle; source_state<=WAIT;
        end
        WAIT: if(completion_sync[1]==request_toggle) begin
          source_rdata<=response_data; source_error<=response_error;
          source_state<=DONE;
        end
        DONE: if(source_valid) source_state<=IDLE;
        default: source_state<=IDLE;
      endcase
    end
  end
  always @(posedge target_clk or posedge target_rst) begin
    if(target_rst) begin
      request_sync<=0; completion_toggle<=0;
      target_valid<=0; target_we<=0; target_addr<=0; target_wdata<=0; target_wstrb<=0;
      response_data<=0; response_error<=0;
    end else begin
      request_sync<={request_sync[0],request_toggle};
      if(!target_valid && request_sync[1]!=completion_toggle) begin
        target_we<=payload_we; target_addr<=payload_addr;
        target_wdata<=payload_data; target_wstrb<=payload_strobes;
        target_valid<=1;
      end else if(target_valid && target_ready) begin
        response_data<=target_rdata; response_error<=target_error;
        completion_toggle<=request_sync[1]; target_valid<=0;
      end
    end
  end
endmodule
`default_nettype wire
