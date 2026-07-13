`timescale 1ns/1ps

// Proves DVP capture, async FIFO, grayscale, and Sobel on unrelated clocks.
module tb_camera_pipeline #(
    parameter integer WIDTH = 8,
    parameter integer HEIGHT = 8,
    parameter logic [31:0] EXPECTED_CRC = 32'h0b70d7fd,
    parameter integer TIMEOUT_NS = 100_000,
    parameter string TEST_NAME = "tb_camera_pipeline"
);
    localparam integer X_W = $clog2(WIDTH);
    localparam integer Y_W = $clog2(HEIGHT);

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cam_pclk, cam_vsync, cam_href;
    logic [7:0] cam_d;
    logic cam_pixel_valid, cam_frame_start, cam_frame_end, cam_line_end, byte_seen;
    logic [X_W-1:0] cam_x;
    logic [Y_W-1:0] cam_y;
    logic [15:0] cam_rgb565;
    logic capture_error;
    logic [3:0] capture_flags;
    logic fifo_valid, fifo_frame_start, fifo_frame_end, fifo_line_end;
    logic [X_W-1:0] fifo_x;
    logic [Y_W-1:0] fifo_y;
    logic [15:0] fifo_rgb565;
    logic overflow_sticky;
    logic [31:0] dropped_pixels;
    logic [15:0] maximum_occupancy;
    logic gray_valid, gray_frame_start, gray_frame_end, gray_line_end;
    logic [X_W-1:0] gray_x;
    logic [Y_W-1:0] gray_y;
    logic [7:0] gray_pixel;
    logic [15:0] aligned_rgb565;
    logic coordinate_error;
    logic sobel_valid;
    logic [X_W-1:0] sobel_x;
    logic [Y_W-1:0] sobel_y;
    logic [7:0] sobel_pixel;
    logic [31:0] accepted_inputs, valid_outputs, frames_started, frames_completed;
    logic [31:0] protocol_errors, output_checksum;
    integer gray_count = 0;
    integer sobel_count = 0;

    always #5 clk = ~clk;
    dvp_camera_model #(.IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT)) camera (.*);

    dvp_rgb565_capture #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) capture (
        .cam_pclk(cam_pclk), .reset(reset), .clear_errors(1'b0),
        .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_d(cam_d), .byte_swap(1'b0),
        .pixel_valid(cam_pixel_valid), .pixel_x(cam_x), .pixel_y(cam_y),
        .pixel_rgb565(cam_rgb565), .frame_start(cam_frame_start),
        .frame_end(cam_frame_end), .line_end(cam_line_end), .byte_seen(byte_seen),
        .capture_error(capture_error), .error_flags(capture_flags)
    );

    camera_stream_cdc #(.FIFO_DEPTH(16), .X_W(X_W), .Y_W(Y_W)) cdc (
        .reset(reset), .write_clk(cam_pclk), .clear_write_errors(1'b0),
        .write_valid(cam_pixel_valid), .write_x(cam_x), .write_y(cam_y),
        .write_rgb565(cam_rgb565), .write_frame_start(cam_frame_start),
        .write_frame_end(cam_frame_end), .write_line_end(cam_line_end),
        .read_clk(clk), .read_valid(fifo_valid), .read_x(fifo_x), .read_y(fifo_y),
        .read_rgb565(fifo_rgb565), .read_frame_start(fifo_frame_start),
        .read_frame_end(fifo_frame_end), .read_line_end(fifo_line_end),
        .overflow_sticky(overflow_sticky), .dropped_pixels(dropped_pixels),
        .maximum_occupancy(maximum_occupancy)
    );

    camera_stream_adapter #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) adapter (
        .clk(clk), .reset(reset), .clear_errors(1'b0),
        .fifo_valid(fifo_valid), .fifo_x(fifo_x), .fifo_y(fifo_y),
        .fifo_rgb565(fifo_rgb565), .fifo_frame_start(fifo_frame_start),
        .fifo_frame_end(fifo_frame_end), .fifo_line_end(fifo_line_end),
        .in_valid(gray_valid), .in_x(gray_x), .in_y(gray_y), .in_gray(gray_pixel),
        .in_rgb565(aligned_rgb565), .frame_start(gray_frame_start),
        .frame_end(gray_frame_end), .line_end(gray_line_end),
        .coordinate_error(coordinate_error)
    );

    conv_pipeline_top #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) pipeline (
        .clk(clk), .reset(reset), .in_valid(gray_valid), .in_x(gray_x),
        .in_y(gray_y), .in_gray(gray_pixel), .out_valid(sobel_valid),
        .out_x(sobel_x), .out_y(sobel_y), .out_pixel(sobel_pixel),
        .accepted_input_pixels(accepted_inputs), .valid_output_pixels(valid_outputs),
        .frames_started(frames_started), .frames_completed(frames_completed),
        .protocol_errors(protocol_errors), .output_checksum(output_checksum)
    );

    always @(posedge clk) begin
        if (gray_valid) begin
            if ((gray_x != (gray_count % WIDTH)) || (gray_y != (gray_count / WIDTH))) begin
                $fatal(1, "system-domain coordinate mismatch at pixel %0d actual=(%0d,%0d)",
                       gray_count, gray_x, gray_y);
            end
            gray_count = gray_count + 1;
        end
        if (sobel_valid) sobel_count = sobel_count + 1;
    end

    initial begin
        repeat (10) @(posedge clk);
        reset = 1'b0;
        wait (!cdc.write_reset_busy && !cdc.read_reset_busy);
        repeat (4) @(posedge clk);
        camera.send_frame(1'b0);
        wait (sobel_count == (WIDTH - 2) * (HEIGHT - 2));
        repeat (5) @(posedge clk);
        if (gray_count != WIDTH * HEIGHT || accepted_inputs != WIDTH * HEIGHT) begin
            $fatal(1, "wrong input count gray=%0d pipeline=%0d", gray_count, accepted_inputs);
        end
        if (valid_outputs != (WIDTH - 2) * (HEIGHT - 2)) begin
            $fatal(1, "wrong Sobel output count %0d", valid_outputs);
        end
        if (output_checksum != EXPECTED_CRC) begin
            $fatal(1, "wrong Sobel CRC expected=%08h actual=%08h",
                   EXPECTED_CRC, output_checksum);
        end
        if (capture_error || overflow_sticky || coordinate_error || protocol_errors != 0) begin
            $fatal(1, "camera pipeline error cap=%b fifo=%b coord=%b protocol=%0d",
                   capture_error, overflow_sticky, coordinate_error, protocol_errors);
        end
        $display("PASS: %s count=%0d CRC=%08h", TEST_NAME, valid_outputs, output_checksum);
        $finish;
    end

    initial begin
        #(TIMEOUT_NS);
        $fatal(1, "camera pipeline test timed out gray=%0d sobel=%0d", gray_count, sobel_count);
    end
endmodule

// Runs the same asynchronous end-to-end proof at the real 320x240 dimensions.
module tb_camera_pipeline_320;
    tb_camera_pipeline #(
        .WIDTH(320),
        .HEIGHT(240),
        .EXPECTED_CRC(32'h6c36985f),
        .TIMEOUT_NS(10_000_000),
        .TEST_NAME("tb_camera_pipeline_320")
    ) test ();
endmodule
