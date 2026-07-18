`timescale 1ns/1ps
module tb_m5_tx_scheduler;
    logic clk=0, reset=1, frame_busy=0, frame_done=0;
    logic arp_pending=0, control_pending=0, echo_pending=0;
    logic camera_pending=0, test_pending=0, frame_start;
    logic [2:0] active_source;
    logic arp_grant, control_grant, echo_grant, camera_grant, test_grant;
    always #5 clk=~clk;
    m5_tx_scheduler u_dut (.*);

    // Completes the currently active frame and leaves the scheduler idle.
    task automatic finish_frame;
        begin
            frame_busy=1; repeat(2) @(posedge clk);
            @(negedge clk); frame_busy=0; frame_done=1;
            @(posedge clk); @(negedge clk); frame_done=0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat(3) @(posedge clk); @(negedge clk); reset=0;
        arp_pending=1; control_pending=1; echo_pending=1;
        camera_pending=1; test_pending=1;
        @(posedge clk); #1;
        if(!arp_grant || active_source!=1)
            $fatal(1,"ARP did not receive first priority: grant=%0b source=%0d start=%0b",
                   arp_grant,active_source,frame_start);
        arp_pending=0; finish_frame();
        if(!control_grant || active_source!=2)
            $fatal(1,"control did not receive second priority: grant=%0b source=%0d start=%0b",
                   control_grant,active_source,frame_start);
        control_pending=0; finish_frame();
        if(!echo_grant || active_source!=3) $fatal(1,"echo did not receive third priority");
        echo_pending=0; finish_frame();
        if(!camera_grant || active_source!=4) $fatal(1,"camera did not receive fourth priority");
        camera_pending=0; finish_frame();
        if(!test_grant || active_source!=5) $fatal(1,"test did not receive final priority");

        frame_busy=1; arp_pending=1; repeat(3) begin
            @(posedge clk); #1;
            if(frame_start || arp_grant) $fatal(1,"scheduler preempted an active frame");
        end
        $display("PASS: tb_m5_tx_scheduler");
        $finish;
    end
endmodule
