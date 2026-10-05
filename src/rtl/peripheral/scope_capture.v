`default_nettype none

// Single-channel deep capture.  The write pointer is a circular pre-trigger
// buffer until the selected edge, followed by post-trigger samples.
module scope_capture (
    input wire clk,
    input wire rst,
    input wire scope_signal,
    input wire we,
    input wire [5:0] off,
    input wire [31:0] wdata,
    input wire window_sel,
    input wire [11:0] window_index,
    output reg [31:0] rdata,
    output reg armed,
    output reg triggered,
    output reg done,
    output reg [12:0] count,
    output reg [11:0] trigger_index
);
  localparam [12:0] DEPTH = 13'd4096;
  localparam [12:0] PRETRIGGER = 13'd2048;
  reg trigger_edge;
  reg [31:0] sample_div;
  reg active_trigger_edge;
  reg [31:0] active_sample_div;
  reg [31:0] div_count;
  reg prev_signal;
  reg [11:0] write_ptr;
  reg [11:0] base_ptr;
  reg [12:0] pre_filled;
  // The chronological MMIO window is asynchronous, so this intentionally
  // maps to LUTRAM. Each sample contains the single measured signal bit.
  (* ram_style = "distributed" *) reg mem [0:4095];
  wire [31:0] sampling_div = armed ? active_sample_div : sample_div;
  wire sample_tick = (div_count >= sampling_div - 1'b1);
  // Trigger detection runs at the full 100 MHz clock. Restricting it to
  // sample_tick can alias a valid periodic input to a constant level and leave
  // SINGLE/dump armed forever when sample_div shares a factor with the period.
  wire edge_hit = active_trigger_edge ? (prev_signal && !scope_signal)
                                : (!prev_signal && scope_signal);
  wire [11:0] window_addr = base_ptr + window_index;

  always @* begin
    if (window_sel) begin
      rdata = {31'd0, mem[window_addr]};
    end else begin
      case (off)
        6'h00: rdata = {29'd0, done, triggered, armed};
        6'h04: rdata = {29'd0, done, triggered, armed};
        6'h08: rdata = {31'd0, trigger_edge};
        6'h0c: rdata = sample_div;
        6'h10: rdata = {19'd0, DEPTH};
        6'h14: rdata = {19'd0, count};
        6'h18: rdata = {20'd0, trigger_index};
        6'h20: rdata = {19'd0, PRETRIGGER};
        6'h24: rdata = {31'd0, active_trigger_edge};
        6'h28: rdata = active_sample_div;
        default: rdata = 32'd0;
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      trigger_edge <= 1'b0;
      sample_div <= 32'd1;
      active_trigger_edge <= 1'b0;
      active_sample_div <= 32'd1;
      div_count <= 32'd0;
      prev_signal <= 1'b0;
      write_ptr <= 12'd0;
      base_ptr <= 12'd0;
      pre_filled <= 13'd0;
      armed <= 1'b0;
      triggered <= 1'b0;
      done <= 1'b0;
      count <= 13'd0;
      trigger_index <= 12'd0;
    end else begin
      prev_signal <= scope_signal;
      if (sample_tick) div_count <= 32'd0;
      else div_count <= div_count + 1'b1;
      if (we) begin
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
            end
            if (wdata[0]) begin
              armed <= 1'b1;
              triggered <= 1'b0;
              done <= 1'b0;
              count <= 13'd0;
              write_ptr <= 12'd0;
              base_ptr <= 12'd0;
              pre_filled <= 13'd0;
              div_count <= 32'd0;
              prev_signal <= scope_signal;
              active_trigger_edge <= trigger_edge;
              active_sample_div <= sample_div;
            end
          end
          6'h08: trigger_edge <= wdata[0];
          6'h0c: sample_div <= (wdata == 0) ? 32'd1 : wdata;
          default: ;
        endcase
      end

      // Reset/rearm has priority over a sample or trigger on the same edge.
      if (armed && !done && !(we && off == 6'h00 && (|wdata[1:0]))) begin
        if (!triggered && edge_hit && pre_filled >= PRETRIGGER) begin
          // Capture the full-rate edge immediately, then restart the divider so
          // all post-trigger samples retain the selected timebase spacing.
          mem[write_ptr] <= scope_signal;
          triggered <= 1'b1;
          base_ptr <= write_ptr - pre_filled[11:0];
          trigger_index <= pre_filled[11:0];
          count <= pre_filled + 1'b1;
          div_count <= 32'd0;
          write_ptr <= write_ptr + 1'b1;
        end else if (sample_tick) begin
          if (!triggered) begin
            mem[write_ptr] <= scope_signal;
            write_ptr <= write_ptr + 1'b1;
            if (pre_filled < PRETRIGGER) pre_filled <= pre_filled + 1'b1;
          end else begin
            mem[write_ptr] <= scope_signal;
            write_ptr <= write_ptr + 1'b1;
            count <= count + 1'b1;
            if (count + 1'b1 >= DEPTH) begin
              done <= 1'b1;
              armed <= 1'b0;
            end
          end
        end
      end
    end
  end
endmodule

`default_nettype wire
