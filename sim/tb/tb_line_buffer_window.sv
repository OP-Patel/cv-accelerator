`timescale 1ns/1ps

// Proves all nine window taps with pixels that encode their raster coordinates.
module tb_line_buffer_window;
    localparam integer WIDTH = 6;
    localparam integer HEIGHT = 5;
    localparam integer X_W = $clog2(WIDTH);
    localparam integer Y_W = $clog2(HEIGHT);

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic in_valid = 1'b0;
    logic [X_W-1:0] in_x = '0;
    logic [Y_W-1:0] in_y = '0;
    logic [7:0] in_pixel = '0;
    logic line_valid;
    logic [X_W-1:0] line_x;
    logic [Y_W-1:0] line_y;
    logic [7:0] row_current, row_previous, row_two_back;
    logic window_valid;
    logic [X_W-1:0] window_x;
    logic [Y_W-1:0] window_y;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    integer checked = 0;

    always #5 clk = ~clk;

    line_buffer_3x3 #(.IMAGE_WIDTH(WIDTH), .X_W(X_W), .Y_W(Y_W)) u_lines (
        .clk(clk), .reset(reset), .in_valid(in_valid), .in_x(in_x), .in_y(in_y),
        .in_pixel(in_pixel), .out_valid(line_valid), .out_x(line_x), .out_y(line_y),
        .row_current(row_current), .row_previous(row_previous), .row_two_back(row_two_back)
    );

    window_3x3 #(.X_W(X_W), .Y_W(Y_W)) u_window (
        .clk(clk), .reset(reset), .in_valid(line_valid), .in_x(line_x), .in_y(line_y),
        .row_current(row_current), .row_previous(row_previous), .row_two_back(row_two_back),
        .window_valid(window_valid), .window_x(window_x), .window_y(window_y),
        .p00(p00), .p01(p01), .p02(p02), .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22)
    );

    // Encodes x in the low nibble and y in the high nibble.
    function automatic logic [7:0] coordinate_pixel(input integer x, input integer y);
        coordinate_pixel = (y << 4) | x;
    endfunction

    // Checks one tap and reports its position on failure.
    task automatic check_tap(
        input logic [7:0] actual,
        input integer expected_x,
        input integer expected_y,
        input integer tap_number
    );
        begin
            if (actual !== coordinate_pixel(expected_x, expected_y)) begin
                $fatal(1, "tap p%0d mismatch at center (%0d,%0d): expected=%h actual=%h",
                       tap_number, window_x, window_y,
                       coordinate_pixel(expected_x, expected_y), actual);
            end
        end
    endtask

    always @(negedge clk) begin
        if (window_valid) begin
            check_tap(p00, window_x-1, window_y-1, 0);
            check_tap(p01, window_x,   window_y-1, 1);
            check_tap(p02, window_x+1, window_y-1, 2);
            check_tap(p10, window_x-1, window_y,   10);
            check_tap(p11, window_x,   window_y,   11);
            check_tap(p12, window_x+1, window_y,   12);
            check_tap(p20, window_x-1, window_y+1, 20);
            check_tap(p21, window_x,   window_y+1, 21);
            check_tap(p22, window_x+1, window_y+1, 22);
            checked = checked + 1;
        end
    end

    initial begin : stimulus
        integer x, y;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        for (y = 0; y < HEIGHT; y = y + 1) begin
            for (x = 0; x < WIDTH; x = x + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_x = x;
                in_y = y;
                in_pixel = coordinate_pixel(x, y);
                if (((x + y) % 4) == 0) begin
                    @(negedge clk);
                    in_valid = 1'b0;
                end
            end
        end
        @(negedge clk);
        in_valid = 1'b0;
        repeat (4) @(negedge clk);
        if (checked != (WIDTH - 2) * (HEIGHT - 2)) begin
            $fatal(1, "window count mismatch: expected=%0d actual=%0d",
                   (WIDTH - 2) * (HEIGHT - 2), checked);
        end
        $display("PASS: tb_line_buffer_window checked %0d windows", checked);
        $finish;
    end
endmodule
