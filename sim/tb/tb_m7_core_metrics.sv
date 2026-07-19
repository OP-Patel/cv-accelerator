`timescale 1ns/1ps
// Verifies exact no-gap frame cadence, pixel totals, and measured core latency.
module tb_m7_core_metrics;
    localparam integer WIDTH=8, HEIGHT=6, X_W=3, Y_W=3;
    logic clk=0,reset=1,clear=0,in_valid=0,out_valid=0;
    logic [X_W-1:0] in_x=0,out_x=0;
    logic [Y_W-1:0] in_y=0,out_y=0;
    logic [31:0] last_latency_cycles,last_frame_interval_cycles;
    logic [31:0] last_accepted_pixels,last_produced_pixels;
    logic [31:0] last_valid_gap_cycles,completed_frames;
    integer frame,x,y;
    always #2.5 clk=~clk;
    m7_core_metrics #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT),.X_W(X_W),.Y_W(Y_W)) u_dut(.*);

    initial begin
        repeat(3) @(posedge clk); reset=0;
        for(frame=0;frame<2;frame=frame+1) begin
            for(y=0;y<HEIGHT;y=y+1) for(x=0;x<WIDTH;x=x+1) begin
                @(negedge clk); in_valid=1; in_x=x; in_y=y;
                if(x>=2 && y>=2) begin
                    out_valid=1; out_x=x-1; out_y=y-1;
                end else out_valid=0;
            end
        end
        @(negedge clk); in_valid=0; out_valid=0;
        repeat(2) @(posedge clk);
        if(last_frame_interval_cycles!=WIDTH*HEIGHT)
            $fatal(1,"frame interval=%0d",last_frame_interval_cycles);
        if(last_accepted_pixels!=WIDTH*HEIGHT ||
           last_produced_pixels!=(WIDTH-2)*(HEIGHT-2))
            $fatal(1,"pixel totals in=%0d out=%0d",last_accepted_pixels,last_produced_pixels);
        if(last_valid_gap_cycles!=0) $fatal(1,"unexpected valid gaps=%0d",last_valid_gap_cycles);
        if(last_latency_cycles==0) $fatal(1,"latency was not measured");
        $display("PASS: tb_m7_core_metrics interval=%0d latency=%0d",
                 last_frame_interval_cycles,last_latency_cycles);
        $finish;
    end
endmodule
