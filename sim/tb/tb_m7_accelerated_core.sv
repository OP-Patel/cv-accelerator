`timescale 1ns/1ps
// Exercises the real CDC-wrapped M7 core with a two-frame synthetic source.
module tb_m7_accelerated_core;
    localparam integer WIDTH=16, HEIGHT=12, X_W=4, Y_W=4;
    logic system_clk=0, reset=1, clear_metrics=0, metrics_request=0;
    logic synthetic_start=0;
    logic [15:0] synthetic_frames=2;
    logic in_valid=0;
    logic [X_W-1:0] in_x=0;
    logic [Y_W-1:0] in_y=0;
    logic [7:0] in_gray=0;
    logic out_valid;
    logic [X_W-1:0] out_x;
    logic [Y_W-1:0] out_y;
    logic [7:0] out_pixel;
    logic core_locked, input_overflow, output_overflow;
    logic metrics_busy, metrics_valid, synthetic_busy;
    logic [15:0] synthetic_completed_frames;
    logic [31:0] latency, interval, accepted, produced, gaps, completed, crc;
    always #5 system_clk=~system_clk;

    m7_accelerated_pipeline #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .FIFO_DEPTH(64),
        .X_W(X_W), .Y_W(Y_W)
    ) u_dut (
        .system_clk(system_clk), .reset(reset), .clear_metrics(clear_metrics),
        .metrics_request(metrics_request), .synthetic_start(synthetic_start),
        .synthetic_frames(synthetic_frames), .in_valid(in_valid), .in_x(in_x),
        .in_y(in_y), .in_gray(in_gray), .out_valid(out_valid), .out_x(out_x),
        .out_y(out_y), .out_pixel(out_pixel), .core_locked(core_locked),
        .input_overflow_sticky(input_overflow),
        .output_overflow_sticky(output_overflow), .metrics_busy(metrics_busy),
        .metrics_valid(metrics_valid), .synthetic_busy(synthetic_busy),
        .synthetic_completed_frames(synthetic_completed_frames),
        .last_latency_cycles(latency),
        .last_frame_interval_cycles(interval),
        .last_accepted_pixels(accepted), .last_produced_pixels(produced),
        .last_valid_gap_cycles(gaps), .completed_frames(completed),
        .last_output_crc(crc)
    );

    initial begin
        repeat(5) @(posedge system_clk);
        reset=0;
        begin : wait_for_lock
            repeat(1000) begin
                @(posedge system_clk);
                if (core_locked) disable wait_for_lock;
            end
            $fatal(1,"M7 core clock did not lock in simulation");
        end
        @(negedge system_clk); synthetic_start=1;
        @(negedge system_clk); synthetic_start=0;
        begin : wait_for_synthetic
            repeat(2000) begin
                @(posedge system_clk);
                if (synthetic_completed_frames==2 && !synthetic_busy)
                    disable wait_for_synthetic;
            end
            $fatal(1,"synthetic M7 benchmark did not complete");
        end
        repeat(4) @(posedge system_clk);
        wait(!metrics_busy);
        @(negedge system_clk); metrics_request=1;
        @(negedge system_clk); metrics_request=0;
        wait(metrics_valid);
        if(input_overflow || output_overflow || accepted!=WIDTH*HEIGHT ||
           produced!=(WIDTH-2)*(HEIGHT-2) || completed<2 || gaps!=0 ||
           latency==0 || interval==0 || crc==0)
            $fatal(1,"core metrics overflow=%0d/%0d in=%0d out=%0d frames=%0d gaps=%0d latency=%0d interval=%0d crc=%08h",
                   input_overflow,output_overflow,accepted,produced,completed,
                   gaps,latency,interval,crc);
        $display("PASS: tb_m7_accelerated_core interval=%0d latency=%0d",interval,latency);
        $finish;
    end
endmodule
