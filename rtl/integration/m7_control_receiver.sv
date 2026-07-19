// Preserves M5 controls and adds version-2 frame-safe M7 configuration/status commands.
module m7_control_receiver #(
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP  = 32'hC0A8_0A02,
    parameter logic [15:0] CONTROL_PORT = 16'd4001
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        clear_errors,
    input  logic        link_up,
    input  logic        frame_done,
    input  logic        frame_valid,
    input  logic [10:0] frame_length,
    input  logic [47:0] destination_mac,
    input  logic [47:0] source_mac,
    input  logic [15:0] ether_type,
    input  logic [31:0] source_ip,
    input  logic [31:0] destination_ip,
    input  logic [7:0]  ip_protocol,
    input  logic        ipv4_checksum_valid,
    input  logic [15:0] ip_total_length,
    input  logic [15:0] udp_source_port,
    input  logic [15:0] udp_destination_port,
    input  logic [15:0] udp_length,
    output logic [10:0] read_address,
    input  logic [7:0]  read_data,
    output logic        parser_busy,
    output logic        command_valid,
    output logic [7:0]  command_version,
    output logic [7:0]  command_opcode,
    output logic        command_stream_id,
    output logic [7:0]  command_status,
    output logic [31:0] command_value,
    output logic [47:0] command_source_mac,
    output logic [31:0] command_source_ip,
    output logic [15:0] command_source_port,
    output logic        session_active,
    output logic        session_stream_id,
    output logic [31:0] session_frame_count,
    output logic [47:0] session_host_mac,
    output logic [31:0] session_host_ip,
    output logic [15:0] session_host_port,
    output logic        session_restart,
    output logic [1:0]  requested_profile,
    output logic        requested_threshold_enable,
    output logic [7:0]  requested_threshold,
    output logic        configuration_toggle,
    output logic [15:0] requested_benchmark_frames,
    output logic        benchmark_toggle,
    output logic [31:0] control_errors
);
    typedef enum logic {IDLE, READ_PAYLOAD} state_t;
    state_t state;
    logic [3:0] payload_index;
    logic [7:0] payload [0:10];
    logic [47:0] saved_mac;
    logic [31:0] saved_ip;
    logic [15:0] saved_port;
    logic [31:0] received_value;
    logic valid_header, valid_v1, valid_v2;

    assign parser_busy = (state != IDLE);
    assign read_address = 11'd42 + payload_index;
    assign received_value = {payload[8], payload[9], payload[10], read_data};
    assign valid_header = payload[0] == "M" && payload[1] == "5" &&
                          payload[2] == "C" && payload[3] == "T";
    assign valid_v1 = valid_header && payload[4] == 1 &&
                      (payload[5] >= 1 && payload[5] <= 3) &&
                      payload[6] <= 1 && payload[7] == 0;
    assign valid_v2 = valid_header && payload[4] == 2 &&
                      (payload[5] >= 1 && payload[5] <= 5) &&
                      payload[6] <= 1 && payload[7] == 0;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            payload_index <= '0;
            saved_mac <= '0;
            saved_ip <= '0;
            saved_port <= '0;
            command_valid <= 1'b0;
            command_version <= '0;
            command_opcode <= '0;
            command_stream_id <= 1'b0;
            command_status <= '0;
            command_value <= '0;
            command_source_mac <= '0;
            command_source_ip <= '0;
            command_source_port <= '0;
            session_active <= 1'b0;
            session_stream_id <= 1'b0;
            session_frame_count <= '0;
            session_host_mac <= '0;
            session_host_ip <= '0;
            session_host_port <= '0;
            session_restart <= 1'b0;
            requested_profile <= 2'd0;
            requested_threshold_enable <= 1'b0;
            requested_threshold <= 8'd128;
            configuration_toggle <= 1'b0;
            requested_benchmark_frames <= 16'd1;
            benchmark_toggle <= 1'b0;
            control_errors <= '0;
        end else begin
            command_valid <= 1'b0;
            session_restart <= 1'b0;
            if (clear_errors)
                control_errors <= '0;
            if (!link_up) begin
                if (session_active)
                    session_restart <= 1'b1;
                session_active <= 1'b0;
            end

            case (state)
                IDLE: begin
                    if (frame_done && frame_valid && destination_mac == FPGA_MAC &&
                        ether_type == 16'h0800 && destination_ip == FPGA_IP &&
                        ip_protocol == 8'h11 && ipv4_checksum_valid &&
                        udp_destination_port == CONTROL_PORT) begin
                        if (udp_length == 16'd20 && ip_total_length == 16'd40 &&
                            frame_length >= 11'd54) begin
                            saved_mac <= source_mac;
                            saved_ip <= source_ip;
                            saved_port <= udp_source_port;
                            payload_index <= 0;
                            state <= READ_PAYLOAD;
                        end else begin
                            control_errors <= control_errors + 1'b1;
                        end
                    end
                end

                READ_PAYLOAD: begin
                    if (payload_index < 11) begin
                        payload[payload_index] <= read_data;
                        payload_index <= payload_index + 1'b1;
                    end else begin
                        state <= IDLE;
                        if (valid_v1 || valid_v2) begin
                            command_valid <= 1'b1;
                            command_version <= payload[4];
                            command_opcode <= payload[5];
                            command_stream_id <= payload[6][0];
                            command_status <= 0;
                            command_value <= received_value;
                            command_source_mac <= saved_mac;
                            command_source_ip <= saved_ip;
                            command_source_port <= saved_port;

                            if (payload[5] == 1) begin
                                session_active <= 1'b1;
                                session_stream_id <= payload[6][0];
                                session_frame_count <= received_value;
                                session_host_mac <= saved_mac;
                                session_host_ip <= saved_ip;
                                session_host_port <= saved_port;
                                session_restart <= 1'b1;
                            end else if (payload[5] == 2) begin
                                session_active <= 1'b0;
                                session_restart <= 1'b1;
                            end else if (payload[5] == 4) begin
                                if (payload[4] != 2 || received_value[31:24] > 2 ||
                                    received_value[23:16] > 1 || received_value[7:0] != 0) begin
                                    command_status <= 8'd2;
                                    control_errors <= control_errors + 1'b1;
                                end else if (session_active) begin
                                    command_status <= 8'd1;
                                end else begin
                                    requested_profile <= received_value[25:24];
                                    requested_threshold_enable <= received_value[16];
                                    requested_threshold <= received_value[15:8];
                                    configuration_toggle <= ~configuration_toggle;
                                end
                            end else if (payload[5] == 5) begin
                                if (received_value == 0 || received_value > 16'hffff) begin
                                    command_status <= 8'd2;
                                    control_errors <= control_errors + 1'b1;
                                end else if (session_active) begin
                                    command_status <= 8'd1;
                                end else begin
                                    requested_benchmark_frames <= received_value[15:0];
                                    benchmark_toggle <= ~benchmark_toggle;
                                end
                            end
                        end else begin
                            control_errors <= control_errors + 1'b1;
                        end
                    end
                end
            endcase
        end
    end
endmodule
