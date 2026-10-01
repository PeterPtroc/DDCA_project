module tb_live_scope;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg signal = 1'b0;
  reg enable = 1'b0;
  reg hold = 1'b0;
  reg [1:0] mode = 2'd3;
  reg edge_sel = 1'b0;
  reg [31:0] sample_div = 32'd1;
  wire [15:0] frame;
  wire frame_valid, trigger_event, waiting, running, forced, single_done;
  wire [31:0] frame_counter;
  integer i;
  reg [31:0] saved_count;
  always #5 clk = ~clk;

  live_scope #(.AUTO_TIMEOUT_SAMPLES(8)) dut (
      .clk(clk), .rst(rst), .scope_signal(signal), .enable(enable), .hold(hold),
      .mode(mode), .trigger_edge(edge_sel), .sample_div(sample_div),
      .wave_frame(frame), .frame_valid(frame_valid), .trigger_event(trigger_event),
      .waiting_trigger(waiting), .running(running), .auto_forced(forced),
      .single_done(single_done), .frame_counter(frame_counter)
  );

  task clocks;
    input integer count;
    integer n;
    begin
      for (n = 0; n < count; n = n + 1) @(posedge clk);
    end
  endtask

  task restart;
    begin
      @(negedge clk); enable = 1'b0;
      clocks(2);
      @(negedge clk); enable = 1'b1;
    end
  endtask

  initial begin
    clocks(3);
    rst = 1'b0;

    // FREE publishes every 16 sampled points and honors sample_div.
    mode = 2'd3;
    sample_div = 32'd2;
    restart();
    for (i = 0; i < 32; i = i + 1) begin
      @(negedge clk); signal = (i % 4) < 2;
      @(posedge clk);
    end
    #1;
    if (frame_counter < 1 || frame === 16'd0 || !running)
      $fatal(1, "FREE/sample_div did not publish a frame");

    saved_count = frame_counter;
    hold = 1'b1;
    clocks(80);
    if (frame_counter !== saved_count || running)
      $fatal(1, "HOLD did not freeze frames");
    hold = 1'b0;

    // NORMAL holds the prior frame without a qualifying edge.
    mode = 2'd1;
    edge_sel = 1'b0;
    sample_div = 32'd1;
    signal = 1'b0;
    restart();
    saved_count = frame_counter;
    clocks(20);
    if (frame_counter !== saved_count || !waiting)
      $fatal(1, "NORMAL updated without a trigger");

    // Rising edge is fixed at LED7 with seven old and eight new samples.
    @(negedge clk); signal = 1'b1;
    clocks(12);
    if (frame_counter !== saved_count + 1 || frame[7] !== 1'b1 ||
        frame[6] !== 1'b0 || frame[8] !== 1'b1)
      $fatal(1, "rising alignment failed frame=%h", frame);

    // Falling edge has the opposite center transition.
    edge_sel = 1'b1;
    signal = 1'b1;
    restart();
    saved_count = frame_counter;
    clocks(12);
    @(negedge clk); signal = 1'b0;
    clocks(12);
    if (frame_counter !== saved_count + 1 || frame[7] !== 1'b0 ||
        frame[6] !== 1'b1 || frame[8] !== 1'b0)
      $fatal(1, "falling alignment failed frame=%h", frame);

    // AUTO forces a frame for a constant signal.
    mode = 2'd0;
    edge_sel = 1'b0;
    signal = 1'b0;
    restart();
    saved_count = frame_counter;
    clocks(12);
    if (frame_counter <= saved_count)
      $fatal(1, "AUTO timeout did not publish a frame");

    // SINGLE publishes exactly one frame and then stops until re-armed.
    mode = 2'd2;
    signal = 1'b0;
    restart();
    saved_count = frame_counter;
    clocks(5);
    @(negedge clk); signal = 1'b1;
    clocks(12);
    if (!single_done || frame_counter !== saved_count + 1 || running)
      $fatal(1, "SINGLE did not complete exactly one frame");
    for (i = 0; i < 40; i = i + 1) begin
      @(negedge clk); signal = ~signal;
      @(posedge clk);
    end
    if (frame_counter !== saved_count + 1)
      $fatal(1, "SINGLE published more than one frame");

    $display("LIVE SCOPE PASS: frames=%0d frame=%h", frame_counter, frame);
    $finish;
  end
endmodule
