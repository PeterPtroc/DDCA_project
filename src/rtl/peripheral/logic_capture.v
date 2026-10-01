`default_nettype none
module logic_capture (
    input wire clk,
    input wire rst,
    input wire [7:0] capture_in,
    input wire we,
    input wire [5:0] off,
    input wire [31:0] wdata,
    input wire window_sel,
    input wire [11:0] window_index,
    input wire [11:0] display_index,
    output reg [31:0] rdata,
    output wire [7:0] display_sample,
    (* ASYNC_REG = "TRUE" *) output reg [7:0] sample_sync,
    output reg armed,
    output reg triggered,
    output reg done,
    output reg [12:0] count,
    output reg [11:0] trigger_index
);
  localparam [12:0] MAX_DEPTH = 13'h1000;
  (* ASYNC_REG = "TRUE" *) reg [7:0] sync1;
  reg [7:0] prev;
  reg [2:0] trig_ch;
  reg trig_edge;
  reg [12:0] depth;
  reg [31:0] sample_div;
  reg [31:0] div_count;
  reg [12:0] pretrigger;
  reg [12:0] active_pretrigger;
  reg [12:0] pre_filled;
  reg [11:0] write_ptr;
  reg [11:0] base_ptr;
  (* ram_style = "distributed" *) reg [7:0] mem[0:4095];

  wire sample_tick = div_count == sample_div - 1'b1;
  wire edge_hit = trig_edge ? (prev[trig_ch] && !sample_sync[trig_ch])
                            : (!prev[trig_ch] && sample_sync[trig_ch]);
  wire [11:0] window_addr = base_ptr + window_index;
  wire [11:0] display_addr = base_ptr + display_index;
  assign display_sample = mem[display_addr];

  always @* begin
    if (window_sel) rdata = {24'd0, mem[window_addr]};
    else
      case (off)
        6'h04: rdata = {29'd0, done, triggered, armed};
        6'h08: rdata = {29'd0, trig_ch};
        6'h0c: rdata = {31'd0, trig_edge};
        6'h10: rdata = {19'd0, depth};
        6'h14: rdata = {19'd0, count};
        6'h18: rdata = {20'd0, trigger_index};
        6'h1c: rdata = sample_div;
        6'h20: rdata = {19'd0, pretrigger};
        default: rdata = 32'd0;
      endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      sync1 <= 8'd0;
      sample_sync <= 8'd0;
      prev <= 8'd0;
      armed <= 1'b0;
      triggered <= 1'b0;
      done <= 1'b0;
      count <= 13'd0;
      write_ptr <= 12'd0;
      base_ptr <= 12'd0;
      depth <= MAX_DEPTH;
      trig_ch <= 3'd0;
      trig_edge <= 1'b0;
      trigger_index <= 12'd0;
      sample_div <= 32'd1;
      div_count <= 32'd0;
      pretrigger <= 13'd0;
      active_pretrigger <= 13'd0;
      pre_filled <= 13'd0;
    end else begin
      sync1 <= capture_in;
      sample_sync <= sync1;
      if (sample_tick) div_count <= 32'd0;
      else div_count <= div_count + 1'b1;

      if (we)
        case (off)
          6'h00: begin
            if (wdata[1]) begin
              armed <= 1'b0;
              triggered <= 1'b0;
              done <= 1'b0;
              count <= 13'd0;
              write_ptr <= 12'd0;
              base_ptr <= 12'd0;
              pre_filled <= 13'd0;
              active_pretrigger <= (pretrigger >= depth) ? depth - 1'b1 : pretrigger;
            end
            if (wdata[0]) begin
              armed <= 1'b1;
              triggered <= 1'b0;
              done <= 1'b0;
              count <= 13'd0;
              write_ptr <= 12'd0;
              base_ptr <= 12'd0;
              pre_filled <= 13'd0;
              active_pretrigger <= (pretrigger >= depth) ? depth - 1'b1 : pretrigger;
              div_count <= 32'd0;
              prev <= sample_sync;
            end
          end
          6'h08: trig_ch <= wdata[2:0];
          6'h0c: trig_edge <= wdata[0];
          6'h10: depth <= (wdata < 1) ? 13'd1 :
                           ((wdata > 4096) ? MAX_DEPTH : wdata[12:0]);
          6'h1c: sample_div <= (wdata < 1) ? 32'd1 : wdata;
          6'h20: pretrigger <= (wdata > 4095) ? 13'd4095 : wdata[12:0];
          default: ;
        endcase

      if (armed && !done && sample_tick) begin
        prev <= sample_sync;
        if (!triggered) begin
          if (edge_hit) begin
            mem[write_ptr] <= sample_sync;
            triggered <= 1'b1;
            base_ptr <= write_ptr - pre_filled[11:0];
            trigger_index <= pre_filled[11:0];
            count <= pre_filled + 1'b1;
            if (pre_filled + 1'b1 >= depth) begin
              done <= 1'b1;
              armed <= 1'b0;
            end else write_ptr <= write_ptr + 1'b1;
          end else if (active_pretrigger != 0) begin
            mem[write_ptr] <= sample_sync;
            write_ptr <= write_ptr + 1'b1;
            if (pre_filled < active_pretrigger) pre_filled <= pre_filled + 1'b1;
          end
        end else begin
          mem[write_ptr] <= sample_sync;
          count <= count + 1'b1;
          if (count + 1'b1 >= depth) begin
            done <= 1'b1;
            armed <= 1'b0;
          end else write_ptr <= write_ptr + 1'b1;
        end
      end
    end
  end
endmodule
`default_nettype wire
