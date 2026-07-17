// Byte-indexed IPv4/UDP echo reply. UDP checksum is deliberately zero for IPv4.
module udp_echo #(
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP  = 32'hC0A8_0A02,
    parameter logic [15:0] UDP_PORT = 16'd4000
) (
    input  logic [47:0] request_source_mac,
    input  logic [31:0] request_source_ip,
    input  logic [15:0] request_source_port,
    input  logic [15:0] request_udp_length,
    input  logic [10:0] reply_index,
    output logic [10:0] request_read_address,
    input  logic [7:0]  request_read_data,
    output logic [10:0] reply_length,
    output logic [7:0]  reply_data
);
    logic [15:0] total_length, ip_checksum;
    logic [31:0] sum;
    always_comb begin
        total_length = 16'd20 + request_udp_length;
        sum = 16'h4500 + total_length + 16'h0000 + 16'h4000 + 16'h4011 +
              FPGA_IP[31:16] + FPGA_IP[15:0] + request_source_ip[31:16] + request_source_ip[15:0];
        sum = (sum & 16'hFFFF) + (sum >> 16);
        sum = (sum & 16'hFFFF) + (sum >> 16);
        ip_checksum = ~sum[15:0];
        reply_length = 11'd34 + request_udp_length;
        request_read_address = reply_index;
        case (reply_index)
            0: reply_data=request_source_mac[47:40]; 1: reply_data=request_source_mac[39:32];
            2: reply_data=request_source_mac[31:24]; 3: reply_data=request_source_mac[23:16];
            4: reply_data=request_source_mac[15:8];  5: reply_data=request_source_mac[7:0];
            6: reply_data=FPGA_MAC[47:40]; 7: reply_data=FPGA_MAC[39:32];
            8: reply_data=FPGA_MAC[31:24]; 9: reply_data=FPGA_MAC[23:16];
            10: reply_data=FPGA_MAC[15:8]; 11: reply_data=FPGA_MAC[7:0];
            12: reply_data=8'h08; 13: reply_data=8'h00; 14: reply_data=8'h45; 15: reply_data=8'h00;
            16: reply_data=total_length[15:8]; 17: reply_data=total_length[7:0];
            18: reply_data=8'h00; 19: reply_data=8'h00; 20: reply_data=8'h40; 21: reply_data=8'h00;
            22: reply_data=8'h40; 23: reply_data=8'h11;
            24: reply_data=ip_checksum[15:8]; 25: reply_data=ip_checksum[7:0];
            26: reply_data=FPGA_IP[31:24]; 27: reply_data=FPGA_IP[23:16];
            28: reply_data=FPGA_IP[15:8]; 29: reply_data=FPGA_IP[7:0];
            30: reply_data=request_source_ip[31:24]; 31: reply_data=request_source_ip[23:16];
            32: reply_data=request_source_ip[15:8]; 33: reply_data=request_source_ip[7:0];
            34: reply_data=UDP_PORT[15:8]; 35: reply_data=UDP_PORT[7:0];
            36: reply_data=request_source_port[15:8]; 37: reply_data=request_source_port[7:0];
            38: reply_data=request_udp_length[15:8]; 39: reply_data=request_udp_length[7:0];
            40,41: reply_data=8'h00;
            default: reply_data=request_read_data;
        endcase
    end
endmodule
