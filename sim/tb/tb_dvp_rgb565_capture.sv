`timescale 1ns/1ps

// Checks byte assembly, coordinates, both byte orders, and odd-line recovery.
module tb_dvp_rgb565_capture;
    localparam integer WIDTH = 8;
    localparam integer HEIGHT = 4;

    logic cam_pclk, cam_vsync, cam_href;
    logic [7:0] cam_d;
    logic reset = 1'b1;
    logic clear_errors = 1'b0;
    logic byte_swap = 1'b0;
    logic pixel_valid;
    logic [2:0] pixel_x;
    logic [1:0] pixel_y;
    logic [15:0] pixel_rgb565;
    logic frame_start, frame_end, line_end, byte_seen, capture_error;
    logic [3:0] error_flags;
    integer received_pixels = 0;
    integer expected_x = 0;
    integer expected_y = 0;

    dvp_camera_model #(.IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT)) camera (.*);
    dvp_rgb565_capture #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .X_W(3), .Y_W(2)
    ) u_dut (.*);

    always @(posedge cam_pclk) begin
        if (pixel_valid) begin
            if ((pixel_x !== expected_x) || (pixel_y !== expected_y)) begin
                $fatal(1, "coordinate mismatch expected=(%0d,%0d) actual=(%0d,%0d)",
                       expected_x, expected_y, pixel_x, pixel_y);
            end
            if (pixel_rgb565 !== camera.coordinate_pixel(expected_x, expected_y)) begin
                $fatal(1, "RGB565 mismatch at (%0d,%0d)", expected_x, expected_y);
            end
            if (frame_start !== ((expected_x == 0) && (expected_y == 0))) begin
                $fatal(1, "frame_start mismatch");
            end
            if (frame_end !== ((expected_x == WIDTH-1) && (expected_y == HEIGHT-1))) begin
                $fatal(1, "frame_end mismatch");
            end
            received_pixels = received_pixels + 1;
            if (expected_x == WIDTH - 1) begin
                expected_x = 0;
                expected_y = expected_y + 1;
            end else begin
                expected_x = expected_x + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge cam_pclk);
        reset = 1'b0;
        camera.send_frame(1'b0);
        if (received_pixels != WIDTH * HEIGHT || capture_error) begin
            $fatal(1, "normal frame failed pixels=%0d errors=%b", received_pixels, error_flags);
        end

        received_pixels = 0;
        expected_x = 0;
        expected_y = 0;
        byte_swap = 1'b1;
        camera.send_frame(1'b1);
        if (received_pixels != WIDTH * HEIGHT || capture_error) begin
            $fatal(1, "swapped frame failed pixels=%0d errors=%b", received_pixels, error_flags);
        end

        received_pixels = 0;
        expected_x = 0;
        expected_y = 0;
        byte_swap = 1'b0;
        camera.send_odd_byte_frame(2);
        if (!error_flags[0]) $fatal(1, "odd-byte line was not detected");

        clear_errors = 1'b1;
        @(posedge cam_pclk);
        clear_errors = 1'b0;
        if (capture_error) $fatal(1, "clear_errors did not clear sticky flags");
        $display("PASS: tb_dvp_rgb565_capture");
        $finish;
    end
endmodule
