`timescale 1ns/1ps
`default_nettype none
// Independent card model driven only by board pins. 16 MiB backing, mode 0,
// delayed MISO (12 ns after falling SCK), command/data CRC and address checks.
module sd_spi_card_model #(
    parameter HIGH_CAPACITY=1, parameter VERSION2=1,
    parameter IMAGE="build/ptrocos_storage/fat16.hex"
) (
    input wire sck,mosi,cs_n,power_off,attached,
    input wire corrupt_next_read,
    output reg miso=1,
    output integer commands=0,reads=0,writes=0,power_cycles=0
);
  bit [7:0] disk[0:16777215];
  byte response[$];
  reg [7:0] frame[0:5],write_buffer[0:513];
  reg [7:0] rx=0,tx=8'hff,next_tx=8'hff;
  integer bits=0,frame_pos=0,write_pos=0,write_sector=0,startup=0,tries=0,busy=0;
  reg tx_response=0,next_response=0,idle=1,app=0,crc_on=0,write_wait=0,writing=0;
  reg corrupt_used=0;
  initial $readmemh(IMAGE,disk);
  function automatic [6:0] crc7(input reg [47:0] bytes6,input integer count);
    reg [6:0] value;reg feedback;integer i;
    begin
      value=0;
      for(i=47;i>=48-count*8;i--) begin
        feedback=value[6]^bytes6[i];value={value[5:0],1'b0};if(feedback) value=value^7'h09;
      end
      crc7=value;
    end
  endfunction
  function automatic [15:0] crc_byte(input reg [15:0] value,input reg [7:0] octet);
    reg [15:0] v;integer i;
    begin
      v=value^{octet,8'd0};
      for(i=0;i<8;i++) v=v[15] ? (v<<1)^16'h1021 : v<<1;
      crc_byte=v;
    end
  endfunction
  task append_register(input bit cid);
    reg [7:0] data[0:15];reg [15:0] crc;integer i;
    begin
      for(i=0;i<16;i++) data[i]=0;
      if(cid) begin
        data[0]=1;data[1]="P";data[2]="T";data[3]="S";data[4]="D";data[5]="C";data[6]="A";data[7]="R";data[8]="D";
      end else if(HIGH_CAPACITY) begin data[0]=8'h40;data[9]=31;end
      else begin data[5]=9;data[6]=3;data[7]=255;data[8]=8'hc0;data[10]=8'h80;end
      response.push_back(255);response.push_back(255);response.push_back(8'hfe);crc=0;
      for(i=0;i<16;i++) begin response.push_back(data[i]);crc=crc_byte(crc,data[i]);end
      response.push_back(crc[15:8]);response.push_back(crc[7:0]);
    end
  endtask
  task process_byte(input reg [7:0] incoming);
    integer cmd,i,sector;reg [31:0] argument;reg [47:0] packet;reg [15:0] crc;
    begin
      if(tx_response) begin if(incoming!=255) $fatal(1,"SD reply MOSI must idle high");end
      else if(busy) busy=busy-1;
      else if(writing) begin
        write_buffer[write_pos]=incoming;write_pos++;
        if(write_pos==514) begin
          crc=0;for(i=0;i<512;i++) crc=crc_byte(crc,write_buffer[i]);
          if(!crc_on || {write_buffer[512],write_buffer[513]}!=crc) $fatal(1,"SD write CRC");
          for(i=0;i<512;i++) disk[write_sector*512+i]=write_buffer[i];
          writes++;response.push_back(5);busy=3;writing=0;
        end
      end else if(write_wait) begin
        if(incoming!=255) begin
          if(incoming!=8'hfe) $fatal(1,"SD write token");writing=1;write_wait=0;write_pos=0;
        end
      end else begin
        if(frame_pos || incoming!=255) begin
          if(!frame_pos && incoming[7:6]!=2'b01) $fatal(1,"SD command start %x",incoming);
          frame[frame_pos]=incoming;frame_pos++;
          if(frame_pos==6) begin
            frame_pos=0;packet={frame[0],frame[1],frame[2],frame[3],frame[4],frame[5]};
            if(frame[5]!={crc7(packet,5),1'b1}) $fatal(1,"SD command CRC %x",packet);
            cmd=frame[0]&63;argument={frame[1],frame[2],frame[3],frame[4]};commands++;
            response.push_back(255);response.push_back(255);response.push_back(255);
            case(cmd)
              0: begin if(startup<74 || argument) $fatal(1,"SD startup");idle=1;crc_on=0;response.push_back(1);end
              8: begin
                if(argument!=32'h1aa) $fatal(1,"CMD8 argument");
                response.push_back(VERSION2 ? 1 : 5);
                if(VERSION2) begin response.push_back(0);response.push_back(0);response.push_back(1);response.push_back(8'haa);end
              end
              55: begin app=1;response.push_back(idle ? 1 : 0);end
              41: begin
                if(!app || argument!=(VERSION2 ? 32'h40000000 : 0)) $fatal(1,"ACMD41");
                app=0;tries++;if(tries>=3) idle=0;response.push_back(idle ? 1 : 0);
              end
              58: begin
                if(idle) $fatal(1,"CMD58 idle");response.push_back(0);
                response.push_back(HIGH_CAPACITY ? 8'hc0 : 8'h80);response.push_back(8'hff);response.push_back(8'h80);response.push_back(0);
              end
              59: begin if(argument!=1) $fatal(1,"CMD59");crc_on=1;response.push_back(0);end
              16: begin if(HIGH_CAPACITY || argument!=512) $fatal(1,"CMD16");response.push_back(0);end
              9,10: begin response.push_back(0);append_register(cmd==10);end
              17,24: begin
                if(idle || !crc_on || (!HIGH_CAPACITY && argument[8:0])) $fatal(1,"SD address/state");
                sector=HIGH_CAPACITY ? argument : argument>>9;
                if(sector<0 || sector>=32768) $fatal(1,"SD sector range");
                response.push_back(0);
                if(cmd==17) begin
                  reads++;response.push_back(255);response.push_back(255);response.push_back(8'hfe);crc=0;
                  for(i=0;i<512;i++) begin response.push_back(disk[sector*512+i]);crc=crc_byte(crc,disk[sector*512+i]);end
                  if(corrupt_next_read && !corrupt_used) begin crc=crc^1;corrupt_used=1;end
                  response.push_back(crc[15:8]);response.push_back(crc[7:0]);
                end else begin write_sector=sector;write_wait=1;end
              end
              default: $fatal(1,"Unsupported SD command %0d",cmd);
            endcase
          end
        end
      end
      next_response=response.size()!=0;
      if(next_response) next_tx=response.pop_front();else next_tx=busy ? 0 : 255;
    end
  endtask
  always @(posedge power_off) begin
    power_cycles++;idle=1;app=0;tries=0;startup=0;crc_on=0;busy=0;
  end
  always @(posedge cs_n or posedge power_off or negedge attached) begin
    response.delete();frame_pos=0;bits=0;rx=0;tx=255;next_tx=255;tx_response=0;next_response=0;
    write_wait=0;writing=0;write_pos=0;miso=1;
  end
  always @(negedge cs_n) begin bits=0;rx=0;tx=255;tx_response=0;miso=1;end
  always @(posedge sck) if(!power_off && attached) begin
    if(cs_n) begin if(!mosi) $fatal(1,"SD startup MOSI");startup++;end
    else begin
      rx={rx[6:0],mosi};bits++;
      if(bits==8) process_byte(rx);
    end
  end
  always @(negedge sck) if(!power_off && attached && !cs_n) begin
    if(bits==8) begin tx=next_tx;tx_response=next_response;bits=0;rx=0;end
    miso<=#12 tx[7-bits];
  end
endmodule
`default_nettype wire
