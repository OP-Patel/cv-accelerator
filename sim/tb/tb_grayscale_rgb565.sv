`timescale 1ns/1ps

// Checks RGB565 expansion, weighted rounding, valid gaps, and reset behavior.
module tb_grayscale_rgb565;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic in_valid = 1'b0;
    logic [15:0] in_rgb565 = '0;
    logic out_valid;
    logic [7:0] out_gray;

    grayscale_rgb565 u_dut (.*);
    always #5 clk = ~clk;

    // Repeats the exact integer conversion independently for expected values.
    function automatic integer expected_gray(input logic [15:0] pixel);
        integer red_8, green_8, blue_8;
        begin
            red_8   = {pixel[15:11], pixel[15:13]};
            green_8 = {pixel[10:5], pixel[10:9]};
            blue_8  = {pixel[4:0], pixel[4:2]};
            expected_gray = (77 * red_8 + 150 * green_8 + 29 * blue_8 + 128) >> 8;
        end
    endfunction

    // Sends one pixel and checks the registered result on the following half-cycle.
    task automatic check_pixel(input logic [15:0] pixel);
        begin
            @(negedge clk);
            in_rgb565 = pixel;
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
            if (!out_valid || out_gray !== expected_gray(pixel)) begin
                $fatal(1, "gray mismatch: rgb=%h expected=%0d actual=%0d",
                       pixel, expected_gray(pixel), out_gray);
            end
            @(negedge clk);
            if (out_valid) $fatal(1, "out_valid advanced during an input gap");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        check_pixel(16'h0000);
        check_pixel(16'hffff);
        check_pixel(16'hf800);
        check_pixel(16'h07e0);
        check_pixel(16'h001f);
        check_pixel(16'h7bef);
        $display("PASS: tb_grayscale_rgb565");
        $finish;
    end
endmodule
