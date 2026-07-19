`timescale 1ns/1ps
// Checks safe/medium/fast timing writes and the post-initialization readback table.
module tb_camera_register_profiles;
    logic clk=0,reset=1,start=0,test_pattern_enable=0;
    logic [1:0] profile_select=0,selected_profile;
    logic command_start,command_write_enable,command_busy=0,command_done=0;
    logic [7:0] command_register,command_write_data,command_read_data=0;
    logic command_ack_error=0,command_timeout_error=0;
    logic init_busy,init_done,init_error,timing_readback_valid;
    logic [15:0] completed_writes,nack_count;
    logic [7:0] product_id,version_id;
    logic [39:0] timing_readback;
    logic [7:0] registers[0:255];
    integer profile;
    always #5 clk=~clk;
    camera_register_init #(
        .CLOCK_HZ(100),.RESET_DELAY_CYCLES(2),.SETTLE_CYCLES(2),
        .ENABLE_M7_PROFILES(1'b1)
    ) u_dut(.*);

    always_ff @(posedge clk) begin
        command_done<=0;
        if(command_start && !command_busy) begin
            command_busy<=1;
            if(command_write_enable) registers[command_register]<=command_write_data;
            else if(command_register==8'h0a) command_read_data<=8'h76;
            else if(command_register==8'h0b) command_read_data<=8'h73;
            else command_read_data<=registers[command_register];
        end else if(command_busy) begin
            command_busy<=0;command_done<=1;
        end
    end

    task automatic run_profile(input integer selected,input logic [7:0] expected_clkrc,
                               input logic [7:0] expected_pclk_div);
        begin
            profile_select=selected;
            @(negedge clk);start=1;@(negedge clk);start=0;
            wait(init_done || init_error);@(posedge clk);
            if(init_error || !timing_readback_valid || selected_profile!=selected)
                $fatal(1,"profile %0d init failed",selected);
            if(timing_readback!={expected_clkrc,8'h04,8'h19,8'h11,expected_pclk_div})
                $fatal(1,"profile %0d readback=%010h",selected,timing_readback);
            if(completed_writes!=66) $fatal(1,"profile %0d writes=%0d",selected,completed_writes);
        end
    endtask

    initial begin
        repeat(3)@(posedge clk);reset=0;
        run_profile(0,8'h01,8'hf1);
        run_profile(1,8'h01,8'hf0);
        run_profile(2,8'h00,8'hf0);
        $display("PASS: tb_camera_register_profiles");
        $finish;
    end
endmodule
