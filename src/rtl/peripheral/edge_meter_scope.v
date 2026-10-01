`default_nettype none

// Hardware measurement for the single synchronized scope input.
module edge_meter_scope #(
    parameter CLOCK_HZ = 100000000,
    parameter MIN_TIMEOUT_TICKS = 10000000,
    parameter INITIAL_TIMEOUT_TICKS = 100000000
) (
    input wire clk,
    input wire rst,
    input wire sample,
    input wire we,
    input wire [4:0] off,
    input wire [31:0] wdata,
    output reg [31:0] rdata,
    output reg valid,
    output reg signal_present,
    output reg averaging,
    output reg [31:0] period_ticks,
    output reg [31:0] high_ticks,
    output reg [31:0] low_ticks,
    output reg [31:0] frequency_hz,
    output reg [31:0] edge_age
);
  reg enable;
  reg prev_sample;
  reg have_rise;
  reg have_fall;
  reg [31:0] ticks;
  reg [31:0] rise_timestamp;
  reg [31:0] fall_timestamp;
  reg dividing;
  reg [5:0] divide_count;
  reg [31:0] divide_divisor;
  reg [31:0] divide_quotient;
  reg [32:0] divide_remainder;

  reg [31:0] period_hist [0:3];
  reg [31:0] high_hist [0:3];
  reg [2:0] hist_count;
  reg [1:0] hist_index;
  reg [33:0] period_sum;
  reg [33:0] high_sum;
  wire rise = !prev_sample && sample;
  wire fall = prev_sample && !sample;
  wire [31:0] measured_period = ticks - rise_timestamp;
  wire [31:0] measured_high = fall_timestamp - rise_timestamp;
  wire [33:0] next_period_sum = hist_count < 3'd4 ?
      period_sum + measured_period :
      period_sum - period_hist[hist_index] + measured_period;
  wire [31:0] frequency_period = averaging && hist_count >= 3'd3 ?
      next_period_sum[33:2] : measured_period;
  wire [31:0] timeout_ticks = (period_ticks != 0 && (period_ticks << 2) > MIN_TIMEOUT_TICKS) ?
      ((period_ticks << 2) > INITIAL_TIMEOUT_TICKS ? INITIAL_TIMEOUT_TICKS : (period_ticks << 2)) :
      MIN_TIMEOUT_TICKS;
  wire [32:0] shifted_remainder = {divide_remainder[31:0], divide_quotient[31]};
  wire subtract_divisor = shifted_remainder >= {1'b0, divide_divisor};
  wire [32:0] next_remainder = subtract_divisor ?
      shifted_remainder - {1'b0, divide_divisor} : shifted_remainder;
  wire [31:0] next_quotient = {divide_quotient[30:0], subtract_divisor};

  always @* begin
    case (off)
      5'h00: rdata = {29'd0, averaging, signal_present, valid};
      5'h04: rdata = period_ticks;
      5'h08: rdata = high_ticks;
      5'h0c: rdata = low_ticks;
      5'h10: rdata = frequency_hz;
      5'h14: rdata = edge_age;
      default: rdata = 32'd0;
    endcase
  end

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      enable <= 1'b1;
      averaging <= 1'b0;
      prev_sample <= 1'b0;
      have_rise <= 1'b0;
      have_fall <= 1'b0;
      ticks <= 32'd0;
      rise_timestamp <= 32'd0;
      fall_timestamp <= 32'd0;
      valid <= 1'b0;
      signal_present <= 1'b0;
      period_ticks <= 32'd0;
      high_ticks <= 32'd0;
      low_ticks <= 32'd0;
      frequency_hz <= 32'd0;
      edge_age <= 32'd0;
      dividing <= 1'b0;
      divide_count <= 6'd0;
      divide_divisor <= 32'd1;
      divide_quotient <= 32'd0;
      divide_remainder <= 33'd0;
      hist_count <= 3'd0;
      hist_index <= 2'd0;
      period_sum <= 34'd0;
      high_sum <= 34'd0;
      for (i = 0; i < 4; i = i + 1) begin
        period_hist[i] <= 32'd0;
        high_hist[i] <= 32'd0;
      end
    end else begin
      ticks <= ticks + 1'b1;
      prev_sample <= sample;
      if (edge_age != 32'hffffffff) edge_age <= edge_age + 1'b1;

      if (we && off == 5'h00) begin
        enable <= wdata[0];
        averaging <= wdata[2];
        if (wdata[1]) begin
          valid <= 1'b0;
          signal_present <= 1'b0;
          have_rise <= 1'b0;
          have_fall <= 1'b0;
          edge_age <= 32'd0;
          hist_count <= 3'd0;
          hist_index <= 2'd0;
          period_sum <= 34'd0;
          high_sum <= 34'd0;
        end
      end

      if (!enable) begin
        valid <= 1'b0;
        signal_present <= 1'b0;
      end else begin
        if (signal_present && edge_age >= timeout_ticks) begin
          valid <= 1'b0;
          signal_present <= 1'b0;
        end else if (!signal_present && edge_age >= INITIAL_TIMEOUT_TICKS) begin
          valid <= 1'b0;
        end

        if (rise) begin
          if (have_rise) begin
            if (!averaging || hist_count < 3'd4) begin
              period_ticks <= measured_period;
              high_ticks <= have_fall ? measured_high : 0;
              low_ticks <= measured_period - (have_fall ? measured_high : 0);
            end
            if (averaging) begin
              if (hist_count < 3'd4) begin
                period_sum <= period_sum + measured_period;
                high_sum <= high_sum + (have_fall ? measured_high : 0);
                period_hist[hist_count[1:0]] <= measured_period;
                high_hist[hist_count[1:0]] <= have_fall ? measured_high : 0;
                hist_count <= hist_count + 1'b1;
                if (hist_count == 3'd3) begin
                  period_ticks <= (period_sum + measured_period) >> 2;
                  high_ticks <= (high_sum + (have_fall ? measured_high : 0)) >> 2;
                  low_ticks <= ((period_sum + measured_period) -
                      (high_sum + (have_fall ? measured_high : 0))) >> 2;
                end
              end else begin
                period_sum <= period_sum - period_hist[hist_index] + measured_period;
                high_sum <= high_sum - high_hist[hist_index] + (have_fall ? measured_high : 0);
                period_hist[hist_index] <= measured_period;
                high_hist[hist_index] <= have_fall ? measured_high : 0;
                hist_index <= hist_index + 1'b1;
                period_ticks <= (period_sum - period_hist[hist_index] + measured_period) >> 2;
                high_ticks <= (high_sum - high_hist[hist_index] +
                    (have_fall ? measured_high : 0)) >> 2;
                low_ticks <= ((period_sum - period_hist[hist_index] + measured_period) -
                    (high_sum - high_hist[hist_index] +
                    (have_fall ? measured_high : 0))) >> 2;
              end
            end
            if (ticks != rise_timestamp && !dividing) begin
              dividing <= 1'b1;
              divide_count <= 6'd0;
              divide_divisor <= frequency_period;
              divide_quotient <= CLOCK_HZ;
              divide_remainder <= 33'd0;
            end
            valid <= have_fall;
            signal_present <= 1'b1;
          end
          rise_timestamp <= ticks;
          have_rise <= 1'b1;
          have_fall <= 1'b0;
          edge_age <= 32'd0;
        end else if (fall && have_rise) begin
          fall_timestamp <= ticks;
          have_fall <= 1'b1;
          edge_age <= 32'd0;
        end
      end

      if (dividing) begin
        divide_remainder <= next_remainder;
        divide_quotient <= next_quotient;
        if (divide_count == 6'd31) begin
          frequency_hz <= next_quotient;
          dividing <= 1'b0;
        end else begin
          divide_count <= divide_count + 1'b1;
        end
      end
    end
  end
endmodule

`default_nettype wire
