`timescale 1ns/1ps
module tb_arp_udp;
    logic [10:0] index,arp_length,udp_length,read_address;
    logic [7:0] arp_data,udp_data,request_data;
    arp_responder u_arp(.request_source_mac(48'h10_20_30_40_50_60),
        .request_source_ip(32'hC0A8_0A01),.reply_index(index),.reply_length(arp_length),.reply_data(arp_data));
    udp_echo u_udp(.request_source_mac(48'h10_20_30_40_50_60),
        .request_source_ip(32'hC0A8_0A01),.request_source_port(16'd5000),
        .request_udp_length(16'd12),.reply_index(index),.request_read_address(read_address),
        .request_read_data(request_data),.reply_length(udp_length),.reply_data(udp_data));
    always_comb request_data=read_address^8'h5A;
    initial begin
        index=0; #1; if(arp_data!=8'h10 || arp_length!=42) $fatal(1,"ARP destination failed");
        index=21; #1; if(arp_data!=8'h02) $fatal(1,"ARP opcode is not reply");
        index=28; #1; if(arp_data!=8'hC0) $fatal(1,"ARP source IP failed");
        index=34; #1; if(udp_data!=8'h0F || udp_length!=46) $fatal(1,"UDP source port/length failed");
        index=36; #1; if(udp_data!=8'h13) $fatal(1,"UDP destination port failed");
        index=42; #1; if(udp_data!=(8'd42^8'h5A) || read_address!=42) $fatal(1,"UDP payload echo failed");
        $display("PASS: tb_arp_udp"); $finish;
    end
endmodule
