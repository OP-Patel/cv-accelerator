// Builds a fixed IPv4/UDP acknowledgement for an accepted M5 control command.
module m5_control_ack #(
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP  = 32'hC0A8_0A02,
    parameter logic [15:0] CONTROL_PORT = 16'd4001
) (
    input  logic [47:0] destination_mac,
    input  logic [31:0] destination_ip,
    input  logic [15:0] destination_port,
    input  logic [7:0]  command_opcode,
    input  logic        command_stream_id,
    input  logic [31:0] command_frame_count,
    input  logic [10:0] frame_index,
    output logic [10:0] frame_length,
    output logic [7:0]  frame_data
);
    logic [31:0] checksum_sum;
    logic [15:0] ip_checksum;

    always_comb begin
        checksum_sum = 16'h4500 + 16'd40 + 16'h0000 + 16'h4000 + 16'h4011 +
                       FPGA_IP[31:16] + FPGA_IP[15:0] +
                       destination_ip[31:16] + destination_ip[15:0];
        checksum_sum = (checksum_sum & 16'hFFFF) + (checksum_sum >> 16);
        checksum_sum = (checksum_sum & 16'hFFFF) + (checksum_sum >> 16);
        ip_checksum  = ~checksum_sum[15:0];
        frame_length = 11'd54;
        case (frame_index)
            0: frame_data=destination_mac[47:40]; 1: frame_data=destination_mac[39:32];
            2: frame_data=destination_mac[31:24]; 3: frame_data=destination_mac[23:16];
            4: frame_data=destination_mac[15:8];  5: frame_data=destination_mac[7:0];
            6: frame_data=FPGA_MAC[47:40]; 7: frame_data=FPGA_MAC[39:32];
            8: frame_data=FPGA_MAC[31:24]; 9: frame_data=FPGA_MAC[23:16];
            10: frame_data=FPGA_MAC[15:8]; 11: frame_data=FPGA_MAC[7:0];
            12: frame_data=8'h08; 13: frame_data=8'h00;
            14: frame_data=8'h45; 15: frame_data=8'h00;
            16: frame_data=8'h00; 17: frame_data=8'd40;
            18: frame_data=8'h00; 19: frame_data=8'h00;
            20: frame_data=8'h40; 21: frame_data=8'h00;
            22: frame_data=8'h40; 23: frame_data=8'h11;
            24: frame_data=ip_checksum[15:8]; 25: frame_data=ip_checksum[7:0];
            26: frame_data=FPGA_IP[31:24]; 27: frame_data=FPGA_IP[23:16];
            28: frame_data=FPGA_IP[15:8]; 29: frame_data=FPGA_IP[7:0];
            30: frame_data=destination_ip[31:24]; 31: frame_data=destination_ip[23:16];
            32: frame_data=destination_ip[15:8]; 33: frame_data=destination_ip[7:0];
            34: frame_data=CONTROL_PORT[15:8]; 35: frame_data=CONTROL_PORT[7:0];
            36: frame_data=destination_port[15:8]; 37: frame_data=destination_port[7:0];
            38: frame_data=8'h00; 39: frame_data=8'd20;
            40,41: frame_data=8'h00;
            42: frame_data="M"; 43: frame_data="5";
            44: frame_data="C"; 45: frame_data="T";
            46: frame_data=8'd1;
            47: frame_data=command_opcode | 8'h80;
            48: frame_data={7'd0,command_stream_id};
            49: frame_data=8'h00;
            50: frame_data=command_frame_count[31:24];
            51: frame_data=command_frame_count[23:16];
            52: frame_data=command_frame_count[15:8];
            default: frame_data=command_frame_count[7:0];
        endcase
    end
endmodule
