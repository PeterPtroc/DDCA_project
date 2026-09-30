`default_nettype none
module crc16_unit (
    input  wire [15:0] crc,
    input  wire [ 7:0] data,
    output reg  [15:0] next_crc
);
  integer i;
  reg [15:0] c;
  always @* begin
    c = crc;
    for (i = 0; i < 8; i = i + 1) begin
      if (c[0] ^ data[i]) c = (c >> 1) ^ 16'hA001;
      else c = c >> 1;
    end
    next_crc = c;
  end
endmodule
`default_nettype wire
