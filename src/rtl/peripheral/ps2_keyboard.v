`default_nettype none
// Receive-only Set-2 transport. USB HID translation is performed by the board PIC.
// 100 MHz local clock; PS/2 pins are data inputs, never used as fabric clocks.
module ps2_keyboard #(
    parameter TIMEOUT_CYCLES=200000,
    parameter FIFO_BITS=5
) (
    input wire clk, rst, ps2_clk, ps2_data,
    input wire valid, we,
    input wire [31:0] addr, wdata,
    input wire [3:0] wstrb,
    output reg [31:0] rdata,
    output wire irq
);
  (* ASYNC_REG="TRUE" *) reg [1:0] clock_sync, data_sync;
  reg [7:0] clock_filter, data_filter;
  reg clock_clean, data_clean, clock_previous;
  wire falling=clock_previous && !clock_clean;
  reg [3:0] bit_index;
  reg [7:0] packet;
  reg parity;
  reg [$clog2(TIMEOUT_CYCLES+1)-1:0] timeout_count;
  reg received, frame_error, timeout_error;
  localparam DEPTH=1<<FIFO_BITS;
  reg [7:0] fifo [0:DEPTH-1];
  reg [FIFO_BITS-1:0] head, tail;
  reg [FIFO_BITS:0] count;
  reg overflow_sticky, frame_sticky, timeout_sticky;
  reg [31:0] received_count, frame_count, timeout_total, overflow_count;
  reg [31:0] clock_edges;
  wire pop=valid && !we && addr[7:2]==1 && count!=0;
  wire push=received && (count<DEPTH || pop);
  wire command=valid && we && addr[7:2]==6 && wstrb[0];
  assign irq=count!=0;
  always @* begin
    case(addr[7:2])
      0:begin
        rdata=0;rdata[8 +: FIFO_BITS+1]=count;
        rdata[3:0]={timeout_sticky,frame_sticky,overflow_sticky,irq};
        rdata[6:4]={bit_index!=0,data_clean,clock_clean};
      end
      1:rdata=count!=0 ? {24'd0,fifo[head]} : 32'd0;
      2:rdata=received_count;
      3:rdata=frame_count;
      4:rdata=timeout_total;
      5:rdata=overflow_count;
      7:rdata=clock_edges;
      default:rdata=0;
    endcase
  end
  always @(posedge clk) begin
    if(rst) begin
      clock_sync<=3;data_sync<=3;clock_filter<=8'hff;data_filter<=8'hff;
      clock_clean<=1;data_clean<=1;clock_previous<=1;
      bit_index<=0;packet<=0;parity<=0;timeout_count<=0;
      received<=0;frame_error<=0;timeout_error<=0;
    end else begin
      clock_sync<={clock_sync[0],ps2_clk};data_sync<={data_sync[0],ps2_data};
      clock_filter<={clock_filter[6:0],clock_sync[1]};
      data_filter<={data_filter[6:0],data_sync[1]};
      if(&clock_filter) clock_clean<=1;
      else if(~|clock_filter) clock_clean<=0;
      if(&data_filter) data_clean<=1;
      else if(~|data_filter) data_clean<=0;
      clock_previous<=clock_clean;
      received<=0;frame_error<=0;timeout_error<=0;
      if(falling) begin
        timeout_count<=0;
        if(bit_index==0) begin
          if(!data_clean) begin bit_index<=1;parity<=0;end
          else frame_error<=1;
        end else if(bit_index<=8) begin
          packet[bit_index-1]<=data_clean;
          parity<=parity^data_clean;bit_index<=bit_index+1'b1;
        end else if(bit_index==9) begin
          parity<=parity^data_clean;bit_index<=10;
        end else begin
          bit_index<=0;
          if(data_clean && parity) received<=1;
          else frame_error<=1;
        end
      end else if(bit_index!=0) begin
        if(timeout_count==TIMEOUT_CYCLES-1) begin
          bit_index<=0;timeout_count<=0;timeout_error<=1;
        end else timeout_count<=timeout_count+1'b1;
      end
    end
  end
  always @(posedge clk) begin
    if(rst) begin
      head<=0;tail<=0;count<=0;
      overflow_sticky<=0;frame_sticky<=0;timeout_sticky<=0;
      received_count<=0;frame_count<=0;timeout_total<=0;overflow_count<=0;clock_edges<=0;
    end else begin
      if(push) begin fifo[tail]<=packet;tail<=tail+1'b1;end
      if(pop) head<=head+1'b1;
      case({push,pop})
        2'b10:count<=count+1'b1;
        2'b01:count<=count-1'b1;
        default:;
      endcase
      if(received) received_count<=received_count+1'b1;
      if(falling) clock_edges<=clock_edges+1'b1;
      if(received && !push) begin overflow_sticky<=1;overflow_count<=overflow_count+1'b1;end
      if(frame_error) begin frame_sticky<=1;frame_count<=frame_count+1'b1;end
      if(timeout_error) begin timeout_sticky<=1;timeout_total<=timeout_total+1'b1;end
      // Explicit software recovery after FIFO loss also resets decoder state.
      // A concurrent byte during flush is intentionally discarded.
      if(command && wdata[0]) begin head<=0;tail<=0;count<=0;end
      if(command && wdata[1]) begin
        overflow_sticky<=0;frame_sticky<=0;timeout_sticky<=0;
        received_count<=0;frame_count<=0;timeout_total<=0;overflow_count<=0;clock_edges<=0;
      end
    end
  end
endmodule
`default_nettype wire
