`timescale 1ns/1ps
`default_nettype none
module tb_pcm_audio;
    reg clk=0,rst=1,valid=0,we=0;reg [3:0] wstrb=15;
    reg [31:0] addr=0,wdata=0;wire [31:0] rdata;wire bit_out,enabled;
    pcm_audio #(.FIFO_BITS(4)) dut(.clk(clk),.rst(rst),.valid(valid),.we(we),.wstrb(wstrb),
        .addr(addr),.wdata(wdata),.rdata(rdata),.audio_bit(bit_out),.audio_enable(enabled));
    always #5 clk=~clk;
    reg [15:0] oracle[0:65535];integer write_index=0,read_index=0,checked=0;
    reg previous_running=0;longint elapsed=0;integer ticks=0;reg [31:0] oracle_rate=0;
    reg pop;reg [15:0] expected;integer simultaneous=0;
    always @(posedge clk) begin
        if(rst || dut.abort_now) begin write_index=0;read_index=0;elapsed=0;ticks=0;previous_running=0;end
        else begin
            pop=dut.pop;
            if(dut.push) begin oracle[write_index]=wdata[15:0];write_index++;end
            if(dut.push && pop) simultaneous++;
            if(pop) begin expected=oracle[read_index];read_index++;end
            if(dut.running) begin
                if(!previous_running) begin elapsed=0;ticks=0;oracle_rate=dut.rate;end
                elapsed++;
                if(dut.tick) begin
                    ticks++;
                    if(elapsed!=(longint'(ticks)*100000000+oracle_rate-1)/oracle_rate)
                        $fatal(1,"Fractional sample clock drift rate=%0d ticks=%0d elapsed=%0d",oracle_rate,ticks,elapsed);
                end
            end
            previous_running=dut.running;
            #1;
            if(pop) begin
                if(dut.pcm!==expected || !dut.sample_valid) $fatal(1,"PCM order mismatch got=%x expected=%x",dut.pcm,expected);
                checked++;
            end
            if(dut.count!=write_index-read_index) $fatal(1,"FIFO count corruption");
        end
    end
    task put(input integer offset,input reg [31:0] data,input reg [3:0] strobes=15);
        @(negedge clk);valid=1;we=1;addr=offset;wdata=data;wstrb=strobes;
        @(negedge clk);valid=0;we=0;wstrb=15;
    endtask
    task restart(input integer rate);
        put(8,2);put(4,rate);
    endtask
    integer ones;reg [15:0] constant_sample;
    initial begin
        repeat(5) @(negedge clk);rst=0;
        if(enabled!==0 || bit_out!==1) $fatal(1,"Unsafe reset output");
        put(8,1);if(!dut.fault) $fatal(1,"Empty start accepted");
        put(4,7999);if(dut.rate!=48000) $fatal(1,"Invalid rate accepted");
        put(8,2);put(4,44100,3);if(dut.rate!=48000) $fatal(1,"Partial rate write accepted");
        put(0,123,1);if(dut.count) $fatal(1,"Partial sample write accepted");
        for(integer r=0;r<4;r++) begin
            restart(r==0 ? 8000 : r==1 ? 11025 : r==2 ? 44100 : 48000);
            for(integer i=0;i<16;i++) put(0,(i*997)&65535);
            put(0,123);if(!dut.overflow || dut.count!=16) $fatal(1,"Full FIFO overwrite");
            put(8,8);put(8,1);put(4,8000);if(!dut.fault) $fatal(1,"Live rate change accepted");put(8,8);
            // 有意在采样边界对已满的 FIFO 同时进行读写。
            for(integer i=16;i<128;i++) begin
                @(negedge clk);
                while(!dut.tick) @(negedge clk);
                valid=1;we=1;addr=0;wdata=(i*997)&65535;
                @(negedge clk);valid=0;we=0;
            end
            put(8,4);put(0,123);if(!dut.overflow) $fatal(1,"Drain accepted a new sample");put(8,8);
            wait(dut.done);@(negedge clk);
            if(dut.played!=128 || dut.underruns || enabled || read_index!=write_index) $fatal(1,"Drain/sample accounting");
        end
        restart(48000);put(0,16'hffff);put(8,1);wait(dut.underruns>=3);@(negedge clk);
        if(!dut.underflow || dut.pcm!=16'h8000) $fatal(1,"Underrun silence");
        put(0,16'h1234);wait(dut.played==2);put(8,2);
        if(enabled || dut.count || dut.underruns || dut.pcm!=16'h8000) $fatal(1,"Cancel flush");
        for(integer c=0;c<4;c++) begin
            constant_sample=c==0 ? 0 : c==1 ? 1 : c==2 ? 32768 : 65535;
            restart(8000);for(integer i=0;i<16;i++) put(0,constant_sample);put(8,1);
            wait(dut.played==1);@(negedge clk);ones=0;
            repeat(65536) begin @(negedge clk);if(bit_out) ones++;end
            if(ones!=constant_sample) $fatal(1,"PDM density mismatch sample=%0d ones=%0d",constant_sample,ones);
            put(8,2);
        end
        put(0,55);put(8,1);@(negedge clk);rst=1;repeat(3) @(negedge clk);rst=0;
        if(enabled || dut.count || bit_out!==1) $fatal(1,"Transaction reset unsafe");
        if(simultaneous<400 || checked<530) $fatal(1,"Insufficient audio coverage %0d %0d",simultaneous,checked);
        $display("PCM AUDIO UNIT PASS samples=%0d simultaneous=%0d rates=8000,11025,44100,48000 PDM=exact",checked,simultaneous);
        $finish;
    end
    initial begin #150000000; $fatal(1,"Audio unit timeout");end
endmodule
`default_nettype wire
