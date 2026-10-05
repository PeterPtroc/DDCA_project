`default_nettype none
// DDR-only, aligned word-copy DMA. Overlapping spans are rejected.
// MMIO offsets: 0 source, 4 destination, 8 word count, c command,
// 10 status {error_code[15:8], error[2], done[1], busy[0]}, 14 words completed.
// Command bits: 0 start, 1 abort after the current bus transaction, 2 clear.
module dma_copy (
    input wire clk, rst,
    input wire mmio_valid, mmio_we,
    input wire [31:0] mmio_addr, mmio_wdata,
    input wire [3:0] mmio_wstrb,
    output reg [31:0] mmio_rdata,
    output wire mem_valid, mem_we,
    output wire [31:0] mem_addr, mem_wdata,
    output wire [3:0] mem_wstrb,
    input wire mem_ready,
    input wire [31:0] mem_rdata,
    input wire mem_error
);
  localparam IDLE=0, READ=1, WRITE=2;
  reg [1:0] state;
  reg [31:0] source, destination, words;
  reg [31:0] active_source, active_destination, remaining, data, completed;
  reg done, error, abort_pending;
  reg [7:0] error_code;
  wire control_write=mmio_valid && mmio_we && mmio_addr[5:2]==3 && mmio_wstrb[0];
  wire abort_now=control_write && mmio_wdata[1];
  wire [34:0] source_end={3'd0,source}+{1'b0,words,2'b00};
  wire [34:0] destination_end={3'd0,destination}+{1'b0,words,2'b00};
  wire bad_alignment=source[1:0]!=0 || destination[1:0]!=0;
  wire bad_range=source[31:27]!=5'b10000 || destination[31:27]!=5'b10000 ||
      source_end>35'h088000000 || destination_end>35'h088000000;
  wire overlap={3'd0,source}<destination_end && {3'd0,destination}<source_end;
  assign mem_valid=state!=IDLE;
  assign mem_we=state==WRITE;
  assign mem_addr=state==WRITE ? active_destination : active_source;
  assign mem_wdata=data;
  assign mem_wstrb=state==WRITE ? 4'hf : 0;
  function [31:0] merge_bytes;
    input [31:0] old_value, new_value;
    input [3:0] strobes;
    integer lane;
    begin
      merge_bytes=old_value;
      for(lane=0;lane<4;lane=lane+1) if(strobes[lane]) merge_bytes[8*lane +: 8]=new_value[8*lane +: 8];
    end
  endfunction
  always @(posedge clk) begin
    if(rst) begin
      state<=IDLE; source<=0; destination<=0; words<=0;
      active_source<=0; active_destination<=0; remaining<=0; data<=0; completed<=0;
      done<=0; error<=0; error_code<=0; abort_pending<=0; mmio_rdata<=0;
    end else begin
      if(mmio_valid && !mmio_we) begin
        case(mmio_addr[5:2])
          0: mmio_rdata<=source;
          1: mmio_rdata<=destination;
          2: mmio_rdata<=words;
          4: mmio_rdata<={16'd0,error_code,5'd0,error,done,(state!=IDLE)};
          5: mmio_rdata<=completed;
          default: mmio_rdata<=0;
        endcase
      end
      if(mmio_valid && mmio_we) begin
        case(mmio_addr[5:2])
          0: source<=merge_bytes(source,mmio_wdata,mmio_wstrb);
          1: destination<=merge_bytes(destination,mmio_wdata,mmio_wstrb);
          2: words<=merge_bytes(words,mmio_wdata,mmio_wstrb);
          default: ;
        endcase
      end
      if(control_write) begin
        if(mmio_wdata[2] && state==IDLE) begin done<=0; error<=0; error_code<=0; end
        if(state!=IDLE && mmio_wdata[1]) abort_pending<=1;
        else if(state==IDLE && mmio_wdata[0]) begin
          completed<=0; done<=0; error<=0; error_code<=0; abort_pending<=0;
          if(words==0) done<=1;
          else if(bad_alignment || bad_range || overlap) begin
            done<=1; error<=1; error_code<=bad_alignment ? 1 : bad_range ? 2 : 3;
          end else begin
            active_source<=source; active_destination<=destination; remaining<=words; state<=READ;
          end
        end
      end
      if(mem_valid && mem_ready) begin
        if(mem_error) begin
          state<=IDLE; done<=1; error<=1; error_code<=4;
        end else if(state==READ) begin
          if(abort_pending || abort_now) begin
            state<=IDLE; done<=1; error<=1; error_code<=5;
          end else begin data<=mem_rdata; state<=WRITE; end
        end else begin
          completed<=completed+1;
          active_source<=active_source+4; active_destination<=active_destination+4;
          remaining<=remaining-1;
          if(abort_pending || abort_now) begin
            state<=IDLE; done<=1; error<=1; error_code<=5;
          end else if(remaining==1) begin state<=IDLE; done<=1; end
          else state<=READ;
        end
      end
    end
  end
endmodule
`default_nettype wire
