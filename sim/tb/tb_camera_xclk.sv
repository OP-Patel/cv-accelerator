`timescale 1ps/1ps

// Measures the MMCM/ODDR 24 MHz output and verifies the startup controls.
module tb_camera_xclk;
    logic clk_100mhz = 1'b0;
    logic reset = 1'b1;
    logic cam_xclk, cam_reset_n, cam_pwdn, clock_ready;
    realtime first_edge, second_edge, high_edge, low_edge;

    always #5000 clk_100mhz = ~clk_100mhz;

    camera_xclk #(.STARTUP_CYCLES(8)) u_dut (.*);

    initial begin
        repeat (6) @(posedge clk_100mhz);
        reset = 1'b0;
        wait (clock_ready);
        if (!cam_reset_n || cam_pwdn) $fatal(1, "camera startup controls were not released");

        @(posedge cam_xclk); first_edge = $realtime;
        @(posedge cam_xclk); second_edge = $realtime;
        if ((second_edge - first_edge < 41_500) || (second_edge - first_edge > 41_850)) begin
            $fatal(1, "XCLK period was %0.1f ps", second_edge - first_edge);
        end

        @(posedge cam_xclk); high_edge = $realtime;
        @(negedge cam_xclk); low_edge = $realtime;
        if ((low_edge - high_edge < 20_700) || (low_edge - high_edge > 21_000)) begin
            $fatal(1, "XCLK high time was %0.1f ps", low_edge - high_edge);
        end
        $display("PASS: tb_camera_xclk period=%0.1f ps", second_edge - first_edge);
        $finish;
    end
endmodule
