`timescale 1ns/1ps
// Checks M5 compatibility plus M7 configuration validation and session interlock.
module tb_m7_control_receiver;
    logic clk=0,reset=1,clear_errors=0,link_up=1,frame_done=0,frame_valid=1;
    logic [10:0] frame_length=54,read_address;
    logic [47:0] destination_mac=48'h02_00_00_00_00_01,source_mac=48'h10_20_30_40_50_60;
    logic [15:0] ether_type=16'h0800,udp_source_port=5000,udp_destination_port=4001,udp_length=20;
    logic [31:0] source_ip=32'hc0a80a01,destination_ip=32'hc0a80a02;
    logic [7:0] ip_protocol=8'h11,read_data;
    logic ipv4_checksum_valid=1;
    logic [15:0] ip_total_length=40;
    logic parser_busy,command_valid,command_stream_id,session_active,session_stream_id;
    logic [7:0] command_version,command_opcode,command_status;
    logic [31:0] command_value,session_frame_count,command_source_ip,session_host_ip,control_errors;
    logic [47:0] command_source_mac,session_host_mac;
    logic [15:0] command_source_port,session_host_port;
    logic session_restart,requested_threshold_enable,configuration_toggle;
    logic benchmark_toggle;
    logic [15:0] requested_benchmark_frames;
    logic [1:0] requested_profile;
    logic [7:0] requested_threshold;
    logic [7:0] memory[0:63];
    always #5 clk=~clk;
    assign read_data=memory[read_address];
    m7_control_receiver u_dut(.*);

    task automatic load(input integer version,input integer opcode,input integer stream,input logic [31:0] value);
        begin
            memory[42]="M";memory[43]="5";memory[44]="C";memory[45]="T";
            memory[46]=version;memory[47]=opcode;memory[48]=stream;memory[49]=0;
            memory[50]=value[31:24];memory[51]=value[23:16];
            memory[52]=value[15:8];memory[53]=value[7:0];
        end
    endtask
    task automatic present;
        begin
            frame_done=1;@(posedge clk);#1;frame_done=0;
            wait(parser_busy);wait(!parser_busy);#1;
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);reset=0;
        load(1,1,0,32'd3);present();
        if(!command_valid || command_version!=1 || !session_active || session_frame_count!=3)
            $fatal(1,"M5 START compatibility failed");
        load(2,4,0,{8'd1,8'd1,8'd96,8'd0});present();
        if(!command_valid || command_status!=1) $fatal(1,"active CONFIG was not rejected");
        load(1,2,0,0);present();
        load(2,4,0,{8'd1,8'd1,8'd96,8'd0});present();
        if(command_status!=0 || requested_profile!=1 || !requested_threshold_enable ||
           requested_threshold!=96) $fatal(1,"valid CONFIG failed");
        load(2,4,0,{8'd3,8'd0,8'd10,8'd0});present();
        if(command_status!=2 || control_errors!=1) $fatal(1,"bad profile was not rejected");
        load(2,5,0,32'd1000);present();
        if(command_status!=0 || requested_benchmark_frames!=1000)
            $fatal(1,"synthetic benchmark request failed");
        $display("PASS: tb_m7_control_receiver");
        $finish;
    end
endmodule
