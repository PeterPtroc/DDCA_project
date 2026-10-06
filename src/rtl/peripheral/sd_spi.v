`default_nettype none
// Mode-0 byte engine. SCK is an output only; all state uses the CPU clock.
module sd_spi (
    input wire clk, rst,
    input wire valid, we,
    input wire [31:0] addr, wdata,
    input wire [3:0] wstrb,
    output reg [31:0] rdata,
    input wire sd_miso, sd_cd_n,
    output reg sd_sck, sd_mosi,
    output wire sd_cs_n, sd_reset
);
  (* ASYNC_REG="TRUE" *) reg [1:0] miso_sync, detect_sync;
  reg power, selected, busy, done, fault, aborted;
  reg [15:0] divider, active_divider, countdown;
  reg [2:0] bit_left;
  reg [7:0] tx_shift, rx_shift, rx_byte;
  reg [31:0] byte_count;
  wire present = !detect_sync[1];
  wire write_low = valid && we && wstrb[0];
  wire control_write = write_low && addr[4:2]==3'd2;
  wire abort_transfer = control_write &&
      (wdata[2] || wdata[0]!=power || wdata[1]!=selected);
  wire [15:0] next_divider = {wstrb[1] ? wdata[15:8] : divider[15:8],
                            wstrb[0] ? wdata[7:0] : divider[7:0]};
  assign sd_reset = !power; // Nexys A7: low powers the card socket.
  assign sd_cs_n = !(power && selected && present);
  always @* begin
    case(addr[4:2])
      3'd0: rdata={24'd0,rx_byte};
      3'd1: rdata={25'd0,aborted,selected,power,present,fault,done,busy};
      3'd2: rdata={30'd0,selected,power};
      3'd3: rdata={16'd0,divider};
      3'd4: rdata=byte_count;
      default: rdata=0;
    endcase
  end
  always @(posedge clk) begin
    if(rst) begin
      miso_sync<=2'b11;detect_sync<=2'b11;
      power<=0;selected<=0;busy<=0;done<=0;fault<=0;aborted<=0;
      divider<=125;active_divider<=125;countdown<=0;bit_left<=0;
      tx_shift<=8'hff;rx_shift<=0;rx_byte<=8'hff;byte_count<=0;
      sd_sck<=0;sd_mosi<=1;
    end else begin
      miso_sync<={miso_sync[0],sd_miso};
      detect_sync<={detect_sync[0],sd_cd_n};
      if(control_write) begin
        power<=wdata[0];selected<=wdata[1];
        if(wdata[3]) begin done<=0;fault<=0;aborted<=0;end
      end
      if(valid && we && addr[4:2]==3'd3 && (|wstrb[1:0]))
        divider<=next_divider<4 ? 16'd4 : next_divider;
      if(abort_transfer || (busy && (!present || !power))) begin
        if(busy) begin fault<=1;aborted<=1;end
        busy<=0;sd_sck<=0;sd_mosi<=1;
      end else begin
        if(busy) begin
          if(countdown!=0) countdown<=countdown-1'b1;
          else begin
            countdown<=active_divider-1'b1;
            if(!sd_sck) begin
              sd_sck<=1;rx_shift<={rx_shift[6:0],miso_sync[1]};
            end else begin
              sd_sck<=0;
              if(bit_left==0) begin
                busy<=0;done<=1;rx_byte<=rx_shift;sd_mosi<=1;
                byte_count<=byte_count+1'b1;
              end else begin
                bit_left<=bit_left-1'b1;tx_shift<={tx_shift[6:0],1'b1};
                sd_mosi<=tx_shift[6];
              end
            end
          end
        end
        if(write_low && addr[4:2]==3'd0) begin
          if(busy || !power || !present) fault<=1;
          else begin
            busy<=1;done<=0;fault<=0;aborted<=0;
            active_divider<=divider;countdown<=divider-1'b1;
            bit_left<=7;tx_shift<=wdata[7:0];rx_shift<=0;
            sd_sck<=0;sd_mosi<=wdata[7];
          end
        end
      end
    end
  end
endmodule
`default_nettype wire
