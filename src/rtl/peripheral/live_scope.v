`default_nettype none

// Low-latency 16-sample display path.  The history register is ordered from
// oldest (bit 0) to newest (bit 15), matching the board LED numbering.
module live_scope #(
    parameter AUTO_TIMEOUT_SAMPLES = 1024
) (
    input wire clk,
    input wire rst,
    input wire scope_signal,
    input wire enable,
    input wire hold,
    input wire [1:0] mode,
    input wire trigger_edge,
    input wire [31:0] sample_div,
    output reg [15:0] wave_frame,
    output reg frame_valid,
    output reg trigger_event,
    output reg waiting_trigger,
    output reg running,
    output reg auto_forced,
    output reg single_done,
    output reg [31:0] frame_counter
);
  localparam MODE_AUTO   = 2'd0;
  localparam MODE_NORMAL = 2'd1;
  localparam MODE_SINGLE = 2'd2;
  localparam MODE_FREE   = 2'd3;

  reg [31:0] divider;
  reg [15:0] history;
  reg last_sample;
  reg capturing_post;
  reg [3:0] post_count;
  reg [15:0] frame_work;
  reg [31:0] auto_age;
  wire [31:0] safe_div = (sample_div == 0) ? 32'd1 : sample_div;
  wire sample_tick = (divider >= safe_div - 1'b1);
  wire edge_hit = trigger_edge ? (last_sample && !scope_signal)
                                : (!last_sample && scope_signal);
  wire [15:0] history_next = {scope_signal, history[15:1]};
  wire auto_timeout = (auto_age >= AUTO_TIMEOUT_SAMPLES - 1);

  always @(posedge clk) begin
    if (rst) begin
      divider <= 32'd0;
      history <= 16'd0;
      last_sample <= 1'b0;
      wave_frame <= 16'd0;
      frame_valid <= 1'b0;
      trigger_event <= 1'b0;
      waiting_trigger <= 1'b0;
      running <= 1'b0;
      auto_forced <= 1'b0;
      single_done <= 1'b0;
      frame_counter <= 32'd0;
      capturing_post <= 1'b0;
      post_count <= 4'd0;
      frame_work <= 16'd0;
      auto_age <= 32'd0;
    end else begin
      frame_valid <= 1'b0;
      trigger_event <= 1'b0;
      auto_forced <= 1'b0;

      if (!enable) begin
        divider <= 32'd0;
        running <= 1'b0;
        waiting_trigger <= 1'b0;
        capturing_post <= 1'b0;
        single_done <= 1'b0;
        auto_age <= 32'd0;
      end else if (hold || (mode == MODE_SINGLE && single_done)) begin
        running <= 1'b0;
        waiting_trigger <= 1'b0;
      end else begin
        running <= 1'b1;
        waiting_trigger <= !capturing_post && (mode != MODE_FREE);
        if (divider >= safe_div - 1'b1) divider <= 32'd0;
        else divider <= divider + 1'b1;

        if (sample_tick) begin
          history <= history_next;
          last_sample <= scope_signal;

          if (capturing_post) begin
            if (post_count == 4'd7) begin
              wave_frame <= frame_work | ({15'd0, scope_signal} << 15);
              frame_valid <= 1'b1;
              frame_counter <= frame_counter + 1'b1;
              capturing_post <= 1'b0;
              trigger_event <= 1'b1;
              if (mode == MODE_SINGLE) begin
                single_done <= 1'b1;
              end
              auto_age <= 32'd0;
            end else begin
              frame_work <= frame_work |
                  ({15'd0, scope_signal} << (8 + post_count));
              post_count <= post_count + 1'b1;
            end
          end else if (mode == MODE_FREE) begin
            if (auto_age == 32'd15) begin
              wave_frame <= history_next;
              frame_valid <= 1'b1;
              frame_counter <= frame_counter + 1'b1;
              auto_age <= 32'd0;
            end else begin
              auto_age <= auto_age + 1'b1;
            end
          end else if (edge_hit) begin
            // Seven pre-trigger samples, trigger at LED7, eight post samples.
            frame_work <= {8'd0, scope_signal, history_next[14:8]};
            post_count <= 4'd0;
            capturing_post <= 1'b1;
            trigger_event <= 1'b1;
            auto_age <= 32'd0;
          end else if (mode == MODE_AUTO && auto_timeout) begin
            wave_frame <= history_next;
            frame_valid <= 1'b1;
            frame_counter <= frame_counter + 1'b1;
            auto_forced <= 1'b1;
            auto_age <= 32'd0;
          end else if (auto_age != 32'hffffffff) begin
            auto_age <= auto_age + 1'b1;
          end
        end
      end
    end
  end
endmodule

`default_nettype wire
