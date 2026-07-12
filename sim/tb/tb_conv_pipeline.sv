`timescale 1ns/1ps

// Exercises complete 8x8 frames with gaps, consecutive frames, and a mid-row reset.
module tb_conv_pipeline;
    localparam integer WIDTH = 8;
    localparam integer HEIGHT = 8;
    localparam integer X_W = $clog2(WIDTH);
    localparam integer Y_W = $clog2(HEIGHT);
    localparam integer MAX_EXPECTED = 512;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic in_valid = 1'b0;
    logic [X_W-1:0] in_x = '0;
    logic [Y_W-1:0] in_y = '0;
    logic [7:0] in_gray = '0;
    logic out_valid;
    logic [X_W-1:0] out_x;
    logic [Y_W-1:0] out_y;
    logic [7:0] out_pixel;
    logic [31:0] accepted_input_pixels, valid_output_pixels;
    logic [31:0] frames_started, frames_completed, protocol_errors, output_checksum;
    integer expected_pixel [0:MAX_EXPECTED-1];
    integer expected_x [0:MAX_EXPECTED-1];
    integer expected_y [0:MAX_EXPECTED-1];
    integer write_index = 0;
    integer read_index = 0;

    always #5 clk = ~clk;

    conv_pipeline_top #(
        .IMAGE_WIDTH(WIDTH), .IMAGE_HEIGHT(HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_dut (.*);

    // Generates simple patterns without sharing any RTL implementation state.
    function automatic integer image_pixel(input integer pattern, input integer x, input integer y);
        case (pattern)
            0: image_pixel = 0;
            1: image_pixel = x < WIDTH/2 ? 0 : 255;
            2: image_pixel = y < HEIGHT/2 ? 0 : 255;
            3: image_pixel = ((x + y) & 1) ? 255 : 0;
            default: image_pixel = (x * 37 + y * 53 + 11) & 255;
        endcase
    endfunction

    // Computes the exact cropped Sobel result centered at (center_x, center_y).
    function automatic integer golden_sobel(
        input integer pattern,
        input integer center_x,
        input integer center_y
    );
        integer p00, p01, p02, p10, p12, p20, p21, p22;
        integer gx, gy, magnitude;
        begin
            p00=image_pixel(pattern,center_x-1,center_y-1);
            p01=image_pixel(pattern,center_x,  center_y-1);
            p02=image_pixel(pattern,center_x+1,center_y-1);
            p10=image_pixel(pattern,center_x-1,center_y);
            p12=image_pixel(pattern,center_x+1,center_y);
            p20=image_pixel(pattern,center_x-1,center_y+1);
            p21=image_pixel(pattern,center_x,  center_y+1);
            p22=image_pixel(pattern,center_x+1,center_y+1);
            gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22;
            gy = -p00 - 2*p01 - p02 + p20 + 2*p21 + p22;
            magnitude = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
            golden_sobel = magnitude > 255 ? 255 : magnitude;
        end
    endfunction

    // Queues the expected result associated with an accepted bottom-right window pixel.
    task automatic queue_expected(input integer pattern, input integer x, input integer y);
        begin
            if ((x >= 2) && (y >= 2)) begin
                expected_x[write_index] = x - 1;
                expected_y[write_index] = y - 1;
                expected_pixel[write_index] = golden_sobel(pattern, x - 1, y - 1);
                write_index = write_index + 1;
            end
        end
    endtask

    // Streams one complete frame and optionally inserts deterministic valid gaps.
    task automatic send_frame(input integer pattern, input integer add_gaps);
        integer x, y;
        begin
            for (y = 0; y < HEIGHT; y = y + 1) begin
                for (x = 0; x < WIDTH; x = x + 1) begin
                    if (add_gaps && (((x * 3 + y * 5) % 7) == 0)) begin
                        @(negedge clk);
                        in_valid = 1'b0;
                    end
                    @(negedge clk);
                    in_valid = 1'b1;
                    in_x = x;
                    in_y = y;
                    in_gray = image_pixel(pattern, x, y);
                    queue_expected(pattern, x, y);
                end
            end
        end
    endtask

    // Waits until every queued expected pixel has appeared, with a timeout.
    task automatic drain_expected;
        integer timeout;
        begin
            @(negedge clk);
            in_valid = 1'b0;
            timeout = 0;
            while ((read_index != write_index) && (timeout < 200)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (read_index != write_index) begin
                $fatal(1, "pipeline drain timeout: expected=%0d received=%0d", write_index, read_index);
            end
        end
    endtask

    always @(negedge clk) begin
        if (out_valid) begin
            if (read_index >= write_index) $fatal(1, "unexpected extra output pixel");
            if ((out_x !== expected_x[read_index]) ||
                (out_y !== expected_y[read_index]) ||
                (out_pixel !== expected_pixel[read_index])) begin
                $fatal(1,
                       "output %0d mismatch: expected (%0d,%0d)=%0d, got (%0d,%0d)=%0d",
                       read_index, expected_x[read_index], expected_y[read_index],
                       expected_pixel[read_index], out_x, out_y, out_pixel);
            end
            read_index = read_index + 1;
        end
    end

    initial begin : stimulus
        integer x;
        repeat (3) @(posedge clk);
        reset = 1'b0;

        send_frame(1, 1);
        drain_expected();
        send_frame(4, 0);
        drain_expected();

        // Two frames are accepted without an artificial frame gap.
        send_frame(2, 0);
        send_frame(3, 0);
        drain_expected();

        // A partial frame is discarded by reset; no stale output may survive.
        for (x = 0; x < WIDTH; x = x + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in_x = x;
            in_y = 0;
            in_gray = image_pixel(4, x, 0);
        end
        @(negedge clk);
        in_valid = 1'b0;
        reset = 1'b1;
        write_index = 0;
        read_index = 0;
        repeat (2) @(negedge clk);
        reset = 1'b0;

        send_frame(4, 1);
        drain_expected();
        if (protocol_errors != 0) $fatal(1, "protocol error counter=%0d", protocol_errors);
        if (valid_output_pixels != (WIDTH-2)*(HEIGHT-2)) begin
            $fatal(1, "final frame output count=%0d", valid_output_pixels);
        end
        $display("PASS: tb_conv_pipeline gaps, reset, and consecutive frames");
        $finish;
    end
endmodule
