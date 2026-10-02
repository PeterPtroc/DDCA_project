`default_nettype none

module rgb_status (
    input wire run,
    input wire hold,
    input wire single_armed,
    input wire error,
    input wire signal_present,
    input wire waiting_trigger,
    output reg rgb0_r,
    output reg rgb0_g,
    output reg rgb0_b,
    output reg rgb1_r,
    output reg rgb1_g,
    output reg rgb1_b
);
  always @* begin
    rgb0_r = 1'b0; rgb0_g = 1'b0; rgb0_b = 1'b0;
    if (error) rgb0_r = 1'b1;
    else if (single_armed) begin rgb0_r = 1'b1; rgb0_g = 1'b1; end
    else if (hold) rgb0_b = 1'b1;
    else if (run) rgb0_g = 1'b1;

    rgb1_r = 1'b0; rgb1_g = 1'b0; rgb1_b = 1'b0;
    if (!signal_present) rgb1_r = 1'b1;
    else if (waiting_trigger) begin rgb1_r = 1'b1; rgb1_g = 1'b1; end
    else rgb1_g = 1'b1;
  end
endmodule

`default_nettype wire
