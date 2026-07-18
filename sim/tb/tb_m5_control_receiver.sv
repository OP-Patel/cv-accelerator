`timescale 1ns/1ps
module tb_m5_control_receiver;
    logic clk=0, reset=1, clear_errors=0, link_up=1;
    logic frame_done=0, frame_valid=1, ipv4_checksum_valid=1;
    logic [10:0] frame_length=54, read_address;
    logic [47:0] destination_mac=48'h02_00_00_00_00_01;
    logic [47:0] source_mac=48'h10_20_30_40_50_60;
    logic [15:0] ether_type=16'h0800;
    logic [31:0] source_ip=32'hC0A8_0A01, destination_ip=32'hC0A8_0A02;
    logic [7:0] ip_protocol=8'h11, read_data;
    logic [15:0] ip_total_length=40, udp_source_port=5000;
    logic [15:0] udp_destination_port=4001, udp_length=20;
    logic parser_busy, command_valid, command_stream_id;
    logic [7:0] command_opcode;
    logic [31:0] command_frame_count;
    logic [47:0] command_source_mac, session_host_mac;
    logic [31:0] command_source_ip, session_host_ip, session_frame_count;
    logic [15:0] command_source_port, session_host_port;
    logic session_active, session_stream_id, session_restart;
    logic [31:0] control_errors;
    logic [7:0] memory [0:63];
    always #5 clk=~clk;
    assign read_data=memory[read_address];

    m5_control_receiver u_dut (.*);

    // Writes one complete fixed-format control payload into the RX memory model.
    task automatic load_control(
        input logic [7:0] opcode,
        input logic [7:0] stream_id,
        input logic [7:0] flags,
        input logic [31:0] frame_count
    );
        begin
            memory[42]="M"; memory[43]="5"; memory[44]="C"; memory[45]="T";
            memory[46]=1; memory[47]=opcode; memory[48]=stream_id; memory[49]=flags;
            memory[50]=frame_count[31:24]; memory[51]=frame_count[23:16];
            memory[52]=frame_count[15:8]; memory[53]=frame_count[7:0];
        end
    endtask

    // Presents the already-validated Ethernet metadata for one receive pulse.
    task automatic present_frame;
        begin
            frame_done=1; @(posedge clk); #1; frame_done=0;
            wait(parser_busy); wait(!parser_busy); #1;
        end
    endtask

    initial begin
        repeat(4) @(posedge clk); reset=0;

        load_control(1,0,0,32'd300);
        present_frame();
        if(!command_valid || !session_active || session_stream_id!=0 ||
           session_frame_count!=300 || session_host_mac!=source_mac ||
           session_host_ip!=source_ip || session_host_port!=udp_source_port)
            $fatal(1,"START did not create the learned session");

        load_control(3,1,0,32'd7);
        present_frame();
        if(!command_valid || command_opcode!=3 || command_stream_id!=1 ||
           command_frame_count!=7 || !session_active)
            $fatal(1,"PING was not accepted without replacing the session");

        load_control(2,0,0,0);
        present_frame();
        if(!command_valid || session_active)
            $fatal(1,"STOP did not invalidate the session");

        load_control(1,2,0,1);
        present_frame();
        if(command_valid || control_errors!=1)
            $fatal(1,"invalid stream identifier was accepted");

        load_control(1,0,0,1);
        present_frame();
        if(!session_active) $fatal(1,"second START failed");
        link_up=0; repeat(2) @(posedge clk); #1;
        if(session_active) $fatal(1,"link loss did not invalidate the session");

        $display("PASS: tb_m5_control_receiver");
        $finish;
    end
endmodule
