`timescale 1ns/1ps
// Checks reference output, binary thresholding, and no mid-frame configuration tear.
module tb_m7_threshold_sobel;
    logic clk=0, reset=1, in_valid=0;
    logic [3:0] in_x=0, in_y=0;
    logic [7:0] in_pixel=0;
    logic requested_threshold_enable=0;
    logic [7:0] requested_threshold=100;
    logic out_valid;
    logic [3:0] out_x,out_y;
    logic [7:0] out_pixel;
    logic active_threshold_enable;
    logic [7:0] active_threshold;
    always #5 clk=~clk;

    m7_threshold_sobel #(.X_W(4),.Y_W(4)) u_dut(.*);

    task automatic send_and_expect(input integer x,input integer y,input integer value,
                                   input integer expected);
        begin
            @(negedge clk); in_valid=1; in_x=x; in_y=y; in_pixel=value;
            @(negedge clk);
            if(!out_valid || out_x!=x || out_y!=y || out_pixel!=expected)
                $fatal(1,"expected (%0d,%0d)=%0d got (%0d,%0d)=%0d",
                       x,y,expected,out_x,out_y,out_pixel);
            in_valid=0;
            @(negedge clk);
        end
    endtask

    initial begin
        repeat(3) @(posedge clk); reset=0;
        send_and_expect(1,1,77,77);

        requested_threshold_enable=1; requested_threshold=100;
        send_and_expect(1,1,99,0);
        requested_threshold=200;
        send_and_expect(2,1,150,255);
        if(active_threshold!=100) $fatal(1,"threshold changed inside frame");

        send_and_expect(1,1,150,0);
        if(active_threshold!=200 || !active_threshold_enable)
            $fatal(1,"new frame did not lock requested threshold");
        $display("PASS: tb_m7_threshold_sobel");
        $finish;
    end
endmodule
