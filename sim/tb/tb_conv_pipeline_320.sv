`timescale 1ns/1ps

// Runs a complete 320x240 coordinate-hash image and checks its Python-derived CRC.
module tb_conv_pipeline_320;
    localparam integer WIDTH = 320;
    localparam integer HEIGHT = 240;
    localparam integer X_W = $clog2(WIDTH);
    localparam integer Y_W = $clog2(HEIGHT);
    localparam logic [31:0] EXPECTED_CRC = 32'he09929fa;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic source_busy, source_done, in_valid;
    logic [X_W-1:0] in_x;
    logic [Y_W-1:0] in_y;
    logic [7:0] in_gray;
    logic out_valid;
    logic [X_W-1:0] out_x;
    logic [Y_W-1:0] out_y;
    logic [7:0] out_pixel;
    logic [31:0] accepted_input_pixels, valid_output_pixels;
    logic [31:0] frames_started, frames_completed, protocol_errors, output_checksum;
    integer timeout;

    always #5 clk = ~clk;

    synthetic_pixel_source #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_source (
        .clk(clk), .reset(reset), .start(start), .pattern_select(3'd5),
        .busy(source_busy), .frame_done(source_done),
        .out_valid(in_valid), .out_x(in_x), .out_y(in_y), .out_gray(in_gray)
    );

    conv_pipeline_top #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_dut (.*);

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        timeout = 0;
        while (!(out_valid && out_x == WIDTH-2 && out_y == HEIGHT-2) && timeout < 80000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (timeout == 80000) $fatal(1, "320x240 regression timed out");
        @(negedge clk);

        if (accepted_input_pixels != WIDTH * HEIGHT) begin
            $fatal(1, "input count mismatch: %0d", accepted_input_pixels);
        end
        if (valid_output_pixels != (WIDTH-2) * (HEIGHT-2)) begin
            $fatal(1, "output count mismatch: %0d", valid_output_pixels);
        end
        if (protocol_errors != 0) $fatal(1, "protocol errors: %0d", protocol_errors);
        if (output_checksum !== EXPECTED_CRC) begin
            $fatal(1, "CRC mismatch: expected=%08h actual=%08h", EXPECTED_CRC, output_checksum);
        end
        $display("PASS: tb_conv_pipeline_320 OUT=%0d CRC=%08h",
                 valid_output_pixels, output_checksum);
        $finish;
    end
endmodule
