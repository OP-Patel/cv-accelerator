`timescale 1ns/1ps
module tb_m5_stream_packetizer;
    localparam integer FRAME_BYTES = 318*238;
    logic clk=0, reset=1, clear_errors=0;
    logic session_active=0, session_restart=0, session_stream_id=0;
    logic [31:0] requested_frame_count=1;
    logic [47:0] host_mac=48'h10_20_30_40_50_60;
    logic [31:0] host_ip=32'hC0A8_0A01;
    logic [15:0] host_port=5000;
    logic fifo_valid=0, fifo_frame_start=0, fifo_frame_end=0;
    logic fifo_discontinuity=0, fifo_stream_id=0;
    logic [7:0] fifo_pixel=0;
    logic fifo_read_enable, packet_ready, packet_done=0;
    logic [10:0] frame_index=0, frame_length;
    logic [7:0] frame_data;
    logic stream_complete;
    logic [31:0] frames_sent, packets_sent, bytes_sent, packet_errors;
    integer pixel_number, observed_packets;
    always #5 clk=~clk;

    m5_stream_packetizer u_dut (.*);

    // Computes the expected standard reflected CRC-32 for one test packet.
    function automatic logic [31:0] expected_crc(
        input integer packet_number,
        input integer payload_length
    );
        logic [31:0] crc;
        logic [7:0] value;
        integer byte_index, bit_index;
        begin
            crc=32'hFFFF_FFFF;
            for(byte_index=0; byte_index<payload_length; byte_index=byte_index+1) begin
                value=(packet_number*1024+byte_index) & 8'hFF;
                for(bit_index=0; bit_index<8; bit_index=bit_index+1)
                    crc=(crc>>1)^((crc[0]^value[bit_index])?32'hEDB88320:32'h0);
            end
            expected_crc=~crc;
        end
    endfunction

    // Checks the held packet descriptor and then releases its packet buffer.
    task automatic consume_packet(input integer packet_number);
        integer expected_length;
        logic [31:0] actual_crc;
        logic [7:0] expected_flags;
        begin
            expected_length=(packet_number==73)?932:1024;
            expected_flags=(packet_number==0)?1:((packet_number==73)?2:0);
            frame_index=42; #1; if(frame_data!="M") $fatal(1,"bad M5 magic");
            frame_index=45; #1; if(frame_data!="V") $fatal(1,"bad M5 magic tail");
            frame_index=48; #1; if(frame_data!=expected_flags) $fatal(1,"bad packet flags");
            frame_index=55; #1; if(frame_data!=packet_number[7:0]) $fatal(1,"bad packet index");
            frame_index=57; #1; if(frame_data!=74) $fatal(1,"bad total packet count");
            frame_index=63; #1; if(frame_data!=expected_length[7:0]) $fatal(1,"bad payload length");
            frame_index=65; #1; if(frame_data!=8'h3E) $fatal(1,"bad Sobel width");
            frame_index=67; #1; if(frame_data!=8'hEE) $fatal(1,"bad Sobel height");
            frame_index=70; #1; actual_crc[31:24]=frame_data;
            frame_index=71; #1; actual_crc[23:16]=frame_data;
            frame_index=72; #1; actual_crc[15:8]=frame_data;
            frame_index=73; #1; actual_crc[7:0]=frame_data;
            if(actual_crc!=expected_crc(packet_number,expected_length))
                $fatal(1,"payload CRC mismatch on packet %0d",packet_number);
            frame_index=74; #1;
            if(frame_data!=((packet_number*1024)&8'hFF)) $fatal(1,"bad first payload byte");
            if(frame_length!=74+expected_length) $fatal(1,"bad Ethernet frame length");
            packet_done=1; @(posedge clk); #1; packet_done=0;
            observed_packets=observed_packets+1;
        end
    endtask

    initial begin
        observed_packets=0;
        repeat(4) @(posedge clk); reset=0;
        session_active=1; session_restart=1; @(posedge clk); #1; session_restart=0;

        for(pixel_number=0; pixel_number<FRAME_BYTES; pixel_number=pixel_number+1) begin
            if(packet_ready) consume_packet(observed_packets);
            fifo_valid=1;
            fifo_frame_start=(pixel_number==0);
            fifo_frame_end=(pixel_number==FRAME_BYTES-1);
            fifo_pixel=pixel_number[7:0];
            #1;
            if(!fifo_read_enable) $fatal(1,"packetizer did not accept offered pixel");
            @(posedge clk); #1;
            fifo_valid=0; fifo_frame_start=0; fifo_frame_end=0;
        end
        if(packet_ready) consume_packet(observed_packets);
        #1;
        if(observed_packets!=74 || packets_sent!=74 || frames_sent!=1 ||
           bytes_sent!=FRAME_BYTES || !stream_complete || packet_errors!=0)
            $fatal(1,"Sobel frame totals are incorrect");
        $display("PASS: tb_m5_stream_packetizer");
        $finish;
    end
    initial begin #20_000_000; $fatal(1,"packetizer test timed out"); end
endmodule
