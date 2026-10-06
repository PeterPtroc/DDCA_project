`default_nettype none
// CPU-clock PCM FIFO and first-order pulse-density DAC. No audio clock CDC.
module pcm_audio #(
    parameter CLOCK_HZ=100000000,
    parameter FIFO_BITS=12
) (
    input wire clk,rst,valid,we,
    input wire [3:0] wstrb,
    input wire [31:0] addr,wdata,
    output reg [31:0] rdata,
    output wire audio_bit,audio_enable
);
    localparam DEPTH=1<<FIFO_BITS;
    (* ram_style="block" *) reg [15:0] fifo[0:DEPTH-1];
    reg [FIFO_BITS-1:0] wrptr,rdptr;
    reg [FIFO_BITS:0] count;
    reg [15:0] head,pcm=16'h8000,residual;
    reg [31:0] rate,phase,played,underruns;
    reg running,draining,done,fault,underflow,overflow,bit_out,sample_valid;
    wire command=valid && we && addr[7:0]==8'h08 && wstrb[0];
    wire abort_now=command && wdata[1];
    wire [32:0] next_phase={1'b0,phase}+{1'b0,rate};
    wire tick=running && next_phase>=CLOCK_HZ;
    wire pop=tick && count!=0;
    wire push_request=valid && we && addr[7:0]==8'h00 && wstrb[1:0]==2'b11;
    wire push=push_request && !draining && (count<DEPTH || pop);
    wire [16:0] density={1'b0,residual}+{1'b0,pcm};
    assign audio_enable=running;
    assign audio_bit=running ? bit_out : 1'b1;
    always @* begin
        case(addr[7:0])
            8'h04:rdata=rate;
            8'h0c:rdata={26'd0,overflow,underflow,fault,done,draining,running};
            8'h10:rdata=count;
            8'h14:rdata=DEPTH;
            8'h18:rdata=played;
            8'h1c:rdata=underruns;
            8'h20:rdata={16'd0,pcm};
            default:rdata=0;
        endcase
    end
    // Registered RAM head is settled long before each tick (>=2083 CPU clocks).
    always @(posedge clk) begin
        head<=fifo[rdptr];
        if(push && !rst && !abort_now) fifo[wrptr]<=wdata[15:0];
    end
    always @(posedge clk) begin
        if(rst || abort_now) begin
            wrptr<=0;rdptr<=0;count<=0;phase<=0;pcm<=16'h8000;residual<=0;bit_out<=1;
            running<=0;draining<=0;done<=0;fault<=0;underflow<=0;overflow<=0;played<=0;underruns<=0;
            sample_valid<=0;
            if(rst) rate<=48000;
        end else begin
            sample_valid<=0;
            if(running) begin
                residual<=density[15:0];bit_out<=density[16];
                phase<=tick ? next_phase-CLOCK_HZ : next_phase;
                if(tick) begin
                    if(count!=0) begin
                        pcm<=head;rdptr<=rdptr+1'b1;played<=played+1;sample_valid<=1;
                    end else if(draining) begin
                        running<=0;draining<=0;done<=1;pcm<=16'h8000;
                    end else begin
                        pcm<=16'h8000;underflow<=1;underruns<=underruns+1;
                    end
                end
            end
            if(push) wrptr<=wrptr+1'b1;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
            if(push_request && !push) overflow<=1;
            if(valid && we && addr[7:0]==8'h04 && wstrb==4'b1111) begin
                if(!running && wdata>=8000 && wdata<=48000) rate<=wdata;
                else fault<=1;
            end
            if(command) begin
                if(wdata[3]) begin fault<=0;underflow<=0;overflow<=0;end
                if(wdata[0]) begin
                    if(!running && count!=0) begin running<=1;draining<=0;done<=0;phase<=0;end
                    else fault<=1;
                end
                if(wdata[2]) begin
                    if(running) draining<=1;
                    else if(!count) done<=1;
                    else fault<=1;
                end
            end
        end
    end
endmodule
`default_nettype wire
