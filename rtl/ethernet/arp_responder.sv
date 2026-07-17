// Byte-indexed ARP reply generator for one compile-time IPv4/MAC address.
module arp_responder #(
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP  = 32'hC0A8_0A02
) (
    input  logic [47:0] request_source_mac,
    input  logic [31:0] request_source_ip,
    input  logic [10:0] reply_index,
    output logic [10:0] reply_length,
    output logic [7:0]  reply_data
);
    assign reply_length = 11'd42;
    always_comb begin
        case (reply_index)
            0: reply_data=request_source_mac[47:40]; 1: reply_data=request_source_mac[39:32];
            2: reply_data=request_source_mac[31:24]; 3: reply_data=request_source_mac[23:16];
            4: reply_data=request_source_mac[15:8];  5: reply_data=request_source_mac[7:0];
            6: reply_data=FPGA_MAC[47:40]; 7: reply_data=FPGA_MAC[39:32];
            8: reply_data=FPGA_MAC[31:24]; 9: reply_data=FPGA_MAC[23:16];
            10: reply_data=FPGA_MAC[15:8]; 11: reply_data=FPGA_MAC[7:0];
            12: reply_data=8'h08; 13: reply_data=8'h06;
            14: reply_data=8'h00; 15: reply_data=8'h01; 16: reply_data=8'h08; 17: reply_data=8'h00;
            18: reply_data=8'h06; 19: reply_data=8'h04; 20: reply_data=8'h00; 21: reply_data=8'h02;
            22: reply_data=FPGA_MAC[47:40]; 23: reply_data=FPGA_MAC[39:32];
            24: reply_data=FPGA_MAC[31:24]; 25: reply_data=FPGA_MAC[23:16];
            26: reply_data=FPGA_MAC[15:8]; 27: reply_data=FPGA_MAC[7:0];
            28: reply_data=FPGA_IP[31:24]; 29: reply_data=FPGA_IP[23:16];
            30: reply_data=FPGA_IP[15:8]; 31: reply_data=FPGA_IP[7:0];
            32: reply_data=request_source_mac[47:40]; 33: reply_data=request_source_mac[39:32];
            34: reply_data=request_source_mac[31:24]; 35: reply_data=request_source_mac[23:16];
            36: reply_data=request_source_mac[15:8]; 37: reply_data=request_source_mac[7:0];
            38: reply_data=request_source_ip[31:24]; 39: reply_data=request_source_ip[23:16];
            40: reply_data=request_source_ip[15:8]; default: reply_data=request_source_ip[7:0];
        endcase
    end
endmodule
