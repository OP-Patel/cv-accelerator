`timescale 1ns/1ps
// Measures two small synthetic DVP frames in independent clock domains.
module tb_camera_timing_monitor;
    logic system_clk=0,system_reset=1,cam_pclk=0,camera_reset=1,clear=0;
    logic cam_vsync=0,cam_href=0;
    logic [31:0] frame_period_system_cycles,frame_pclk_edges,active_bytes;
    logic [15:0] line_pclk_edges,active_lines;
    logic [127:0] source_snapshot;
    integer frame,line,byte_index;
    always #5 system_clk=~system_clk;
    always #10 cam_pclk=~cam_pclk;
    camera_timing_monitor u_dut(.*);

    task automatic send_frame;
        begin
            cam_vsync=1;repeat(3)@(posedge cam_pclk);cam_vsync=0;
            repeat(2)@(posedge cam_pclk);
            for(line=0;line<3;line=line+1) begin
                cam_href=1;for(byte_index=0;byte_index<8;byte_index=byte_index+1)@(posedge cam_pclk);
                cam_href=0;repeat(2)@(posedge cam_pclk);
            end
            repeat(3)@(posedge cam_pclk);
        end
    endtask
    initial begin
        repeat(3)@(posedge system_clk);system_reset=0;camera_reset=0;
        send_frame();send_frame();
        cam_vsync=1;repeat(3)@(posedge cam_pclk);cam_vsync=0;
        repeat(3)@(posedge system_clk);
        if(active_bytes!=24 || active_lines!=3)
            $fatal(1,"activity bytes=%0d lines=%0d",active_bytes,active_lines);
        if(frame_pclk_edges==0 || line_pclk_edges==0 || frame_period_system_cycles==0)
            $fatal(1,"timing counters were not populated");
        $display("PASS: tb_camera_timing_monitor SYS=%0d PCLK=%0d",
                 frame_period_system_cycles,frame_pclk_edges);
        $finish;
    end
endmodule
