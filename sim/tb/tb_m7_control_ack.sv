`timescale 1ns/1ps
// Checks the complete M7 status acknowledgement, including its IPv4 checksum.
module tb_m7_control_ack;
    logic [47:0] destination_mac = 48'h10_20_30_40_50_60;
    logic [31:0] destination_ip = 32'hc0a8_0a01;
    logic [15:0] destination_port = 16'd4001;
    logic [7:0] command_version = 8'd2;
    logic [7:0] command_opcode = 8'd3;
    logic command_stream_id = 1'b0;
    logic [7:0] reply_status = 8'd0;
    logic [31:0] reply_value = 32'h4d37_0001;
    logic [10:0] frame_index;
    logic [10:0] frame_length;
    logic [7:0] frame_data;
    logic [7:0] frame [0:53];
    logic [31:0] checksum_sum;
    integer index;

    m7_control_ack u_dut (
        .destination_mac(destination_mac), .destination_ip(destination_ip),
        .destination_port(destination_port), .command_version(command_version),
        .command_opcode(command_opcode), .command_stream_id(command_stream_id),
        .reply_status(reply_status), .reply_value(reply_value),
        .frame_index(frame_index), .frame_length(frame_length), .frame_data(frame_data)
    );

    initial begin
        for (index = 0; index < 54; index = index + 1) begin
            frame_index = index;
            #1;
            frame[index] = frame_data;
        end

        if (frame_length != 54)
            $fatal(1, "M7 ACK length is not 54 bytes");
        if ({frame[24], frame[25]} != 16'ha571)
            $fatal(1, "M7 ACK IPv4 checksum is %04x, expected a571",
                   {frame[24], frame[25]});

        checksum_sum = 0;
        for (index = 14; index < 34; index = index + 2)
            checksum_sum = checksum_sum + {frame[index], frame[index+1]};
        checksum_sum = (checksum_sum & 16'hffff) + (checksum_sum >> 16);
        checksum_sum = (checksum_sum & 16'hffff) + (checksum_sum >> 16);
        if (checksum_sum[15:0] != 16'hffff)
            $fatal(1, "M7 ACK IPv4 header checksum does not validate");

        if ({frame[42], frame[43], frame[44], frame[45]} != 32'h4d35_4354 ||
            frame[46] != 2 || frame[47] != 8'h83 || frame[48] != 0 ||
            frame[49] != 0 ||
            {frame[50], frame[51], frame[52], frame[53]} != 32'h4d37_0001)
            $fatal(1, "M7 status acknowledgement payload is malformed");

        $display("PASS: tb_m7_control_ack");
        $finish;
    end
endmodule
