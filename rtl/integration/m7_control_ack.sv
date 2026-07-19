// Emits the unchanged 12-byte control reply with version-2 status/value support.
module m7_control_ack #(
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP  = 32'hC0A8_0A02,
    parameter logic [15:0] CONTROL_PORT = 16'd4001
) (
    input  logic [47:0] destination_mac,
    input  logic [31:0] destination_ip,
    input  logic [15:0] destination_port,
    input  logic [7:0]  command_version,
    input  logic [7:0]  command_opcode,
    input  logic        command_stream_id,
    input  logic [7:0]  reply_status,
    input  logic [31:0] reply_value,
    input  logic [10:0] frame_index,
    output logic [10:0] frame_length,
    output logic [7:0]  frame_data
);
    logic [15:0] ip_checksum;
    assign frame_length = 54;
    assign ip_checksum = 16'hb11a + FPGA_IP[31:16] + FPGA_IP[15:0] +
                         destination_ip[31:16] + destination_ip[15:0];

    always_comb begin
        frame_data = 0;
        if (frame_index < 6)
            frame_data = destination_mac[47-(frame_index*8) -: 8];
        else if (frame_index < 12)
            frame_data = FPGA_MAC[47-((frame_index-6)*8) -: 8];
        else case (frame_index)
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
            46: frame_data=command_version;
            47: frame_data=command_opcode | 8'h80;
            48: frame_data={7'd0,command_stream_id};
            49: frame_data=(command_version == 1) ? 8'd0 : reply_status;
            50: frame_data=reply_value[31:24];
            51: frame_data=reply_value[23:16];
            52: frame_data=reply_value[15:8];
            default: frame_data=reply_value[7:0];
        endcase
    end
endmodule
