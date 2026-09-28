`default_nettype none
module soc_top(input wire clk,input wire rst,input wire [15:0] sw,input wire [4:0] btn,input wire [7:0] capture_in,output wire [15:0] led,output wire uart_tx,output wire pwm_out,output wire [31:0] test_result,output wire capture_done);
 wire [31:0] ia,id,da,dw,dr,dmem_rdata; wire dv,dwe; wire rv,rwe; wire [31:0] rpc,ri,rd; wire [4:0] rr; wire es; wire [1:0] ef, wf; wire fl,br,bt,crc;
 wire [31:0] mmio_r; wire [15:0] mmio_led; wire [31:0] mmio_result; wire mmio_uart,mmio_pwm; wire ca,ct; wire [7:0] cs;
 rv32_core cpu(clk,rst,ia,id,dv,dwe,da,dw,dr,rv,rpc,ri,rwe,rr,rd,es,ef,wf,fl,br,bt,crc);
 imem im(ia,id); dmem dm(clk,rst,dv&&dwe,da,dw,dmem_rdata);
 mmio_decoder bus(clk,rst,dv,dwe,da,dw,sw,btn,capture_in,rv,es,ef,wf,fl,br,bt,crc,mmio_r,mmio_led,mmio_result,mmio_uart,mmio_pwm,cs,ca,ct,capture_done);
 assign dr=(da[31:28]==4'h4)?mmio_r:dmem_rdata; assign led=mmio_led; assign test_result=mmio_result; assign uart_tx=mmio_uart; assign pwm_out=mmio_pwm;
endmodule
`default_nettype wire
