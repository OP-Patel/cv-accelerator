`timescale 1ns/1ps
module tb_ethernet_frames;
    logic clk=0, reset=1, tx_start=0, tx_ready=1;
    logic [10:0] tx_length=60, tx_index;
    logic [7:0] tx_source, tx_output;
    logic tx_valid, tx_last, tx_busy, tx_done, tx_len_error;
    logic [7:0] wire_bytes[0:80]; integer wire_count=0;
    logic [7:0] rx_input, rx_read_data; logic rx_input_valid=0, rx_start=0, rx_end=0;
    logic [10:0] rx_read_address=0, rx_length;
    logic rx_done,rx_valid,ipv4_ok;
    logic [47:0] dmac,smac; logic [15:0] etype,arpop,usrc,udst,ulen;
    logic [31:0] sip,dip,good,badfcs,runt,oversize,rxerrs; logic [7:0] proto;
    logic [31:0] protoerrs,seqgaps; logic [15:0] iptotal;
    always #5 clk=~clk;
    always_comb begin
        if(tx_index<6) tx_source=8'hFF;
        else if(tx_index<12) tx_source=tx_index;
        else if(tx_index==12) tx_source=8'h88;
        else if(tx_index==13) tx_source=8'hB5;
        else tx_source=tx_index^8'hA5;
    end
    ethernet_frame_tx u_tx(.clk(clk),.reset(reset),.start(tx_start),.frame_length(tx_length),
        .frame_data_index(tx_index),.frame_data(tx_source),.output_data(tx_output),
        .output_valid(tx_valid),.output_last(tx_last),.output_ready(tx_ready),
        .busy(tx_busy),.done(tx_done),.length_error(tx_len_error));
    always @(negedge clk) if(tx_valid&&tx_ready) begin wire_bytes[wire_count]=tx_output; wire_count=wire_count+1; end
    ethernet_frame_rx u_rx(.clk(clk),.reset(reset),.clear_errors(1'b0),.byte_data(rx_input),
        .byte_valid(rx_input_valid),.frame_start(rx_start),.frame_end(rx_end),
        .mii_rx_error(1'b0),.odd_nibble(1'b0),.read_address(rx_read_address),.read_data(rx_read_data),
        .frame_done(rx_done),.frame_valid(rx_valid),.frame_length(rx_length),
        .destination_mac(dmac),.source_mac(smac),.ether_type(etype),.source_ip(sip),
        .destination_ip(dip),.arp_opcode(arpop),.udp_source_port(usrc),
        .udp_destination_port(udst),.udp_length(ulen),.ip_protocol(proto),
        .ip_total_length(iptotal),
        .ipv4_checksum_valid(ipv4_ok),.good_frames(good),.bad_fcs_frames(badfcs),
        .runt_frames(runt),.oversize_frames(oversize),.rx_error_frames(rxerrs),
        .protocol_error_frames(protoerrs),.sequence_gap_frames(seqgaps));
    task automatic replay(input logic corrupt);
        integer n;
        begin
            @(negedge clk); rx_start=1;
            for(n=0;n<wire_count;n=n+1) begin
                rx_input=wire_bytes[n] ^ ((corrupt&&n==20)?8'h01:8'h00); rx_input_valid=1;
                @(negedge clk); rx_start=0;
            end
            rx_input_valid=0; rx_end=1; @(negedge clk); rx_end=0; wait(rx_done); @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(posedge clk); reset=0;
        @(negedge clk); tx_start=1; @(negedge clk); tx_start=0; wait(tx_done); @(negedge clk);
        if(wire_count!=72 || tx_len_error) $fatal(1,"encoded frame length=%0d",wire_count);
        replay(0);
        if(!rx_valid || rx_length!=60 || etype!=16'h88B5 || good!=1) $fatal(1,"valid frame rejected");
        replay(1);
        if(rx_valid || badfcs!=1 || good!=1) $fatal(1,"corrupted FCS classification failed");
        $display("PASS: tb_ethernet_frames"); $finish;
    end
endmodule
