`timescale 1ns/1ps

// Checks signed Sobel arithmetic, coordinate delay, saturation, and throughput.
module tb_sobel3x3;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic in_valid = 1'b0;
    logic [3:0] in_x = '0;
    logic [3:0] in_y = '0;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic out_valid;
    logic [3:0] out_x, out_y;
    logic [7:0] out_pixel;
    integer expected [0:4];
    integer expected_x [0:4];
    integer checked = 0;

    always #5 clk = ~clk;

    sobel3x3 #(.X_W(4), .Y_W(4)) u_dut (.*);

    // Computes the bit-exact expected Sobel magnitude for the current taps.
    function automatic integer expected_sobel;
        integer gx, gy, magnitude;
        begin
            gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22;
            gy = -p00 - 2*p01 - p02 + p20 + 2*p21 + p22;
            magnitude = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
            expected_sobel = magnitude > 255 ? 255 : magnitude;
        end
    endfunction

    always @(negedge clk) begin
        if (out_valid) begin
            if (out_pixel !== expected[checked] || out_x !== expected_x[checked]) begin
                $fatal(1, "Sobel mismatch at item %0d: expected x=%0d pixel=%0d, got x=%0d pixel=%0d",
                       checked, expected_x[checked], expected[checked], out_x, out_pixel);
            end
            checked = checked + 1;
        end
    end

    // Presents a window for one clock without inserting a gap.
    task automatic send_window(input integer index, input integer kind);
        begin
            @(negedge clk);
            in_valid = 1'b1;
            in_x = index;
            in_y = 4'd7;
            case (kind)
                0: begin p00=0; p01=0; p02=0; p10=0; p11=0; p12=0; p20=0; p21=0; p22=0; end
                1: begin p00=0; p01=0; p02=255; p10=0; p11=0; p12=255; p20=0; p21=0; p22=255; end
                2: begin p00=0; p01=0; p02=0; p10=10; p11=20; p12=30; p20=40; p21=50; p22=60; end
                3: begin p00=255; p01=255; p02=255; p10=0; p11=0; p12=0; p20=0; p21=0; p22=0; end
                default: begin p00=2; p01=4; p02=8; p10=16; p11=32; p12=64; p20=128; p21=7; p22=3; end
            endcase
            expected[index] = expected_sobel();
            expected_x[index] = index;
        end
    endtask

    initial begin
        p00=0; p01=0; p02=0; p10=0; p11=0; p12=0; p20=0; p21=0; p22=0;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        send_window(0, 0);
        send_window(1, 1);
        send_window(2, 2);
        send_window(3, 3);
        send_window(4, 4);
        @(negedge clk);
        in_valid = 1'b0;
        repeat (8) @(negedge clk);
        if (checked != 5) $fatal(1, "expected 5 Sobel results, got %0d", checked);
        $display("PASS: tb_sobel3x3");
        $finish;
    end
endmodule
