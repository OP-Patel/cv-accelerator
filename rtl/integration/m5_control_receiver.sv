// Validates the fixed 12-byte M5 control protocol and owns the learned session.
module m5_control_receiver #(
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
    output logic [7:0]  command_opcode,
    output logic        command_stream_id,
    output logic [31:0] command_frame_count,
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
    output logic [31:0] control_errors
);
    typedef enum logic {IDLE, READ_PAYLOAD} state_t;
    state_t state;
    logic [3:0] payload_index;
    logic [7:0] payload [0:10];
    logic [47:0] saved_mac;
    logic [31:0] saved_ip;
    logic [15:0] saved_port;

    assign parser_busy  = (state != IDLE);
    assign read_address = 11'd42 + payload_index;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state               <= IDLE;
            payload_index       <= '0;
            saved_mac           <= '0;
            saved_ip            <= '0;
            saved_port          <= '0;
            command_valid       <= 1'b0;
            command_opcode      <= '0;
            command_stream_id   <= 1'b0;
            command_frame_count <= '0;
            command_source_mac  <= '0;
            command_source_ip   <= '0;
            command_source_port <= '0;
            session_active      <= 1'b0;
            session_stream_id   <= 1'b0;
            session_frame_count <= '0;
            session_host_mac    <= '0;
            session_host_ip     <= '0;
            session_host_port   <= '0;
            session_restart     <= 1'b0;
            control_errors      <= '0;
        end else begin
            command_valid   <= 1'b0;
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
                    if (frame_done && frame_valid &&
                        destination_mac == FPGA_MAC && ether_type == 16'h0800 &&
                        destination_ip == FPGA_IP && ip_protocol == 8'h11 &&
                        ipv4_checksum_valid && udp_destination_port == CONTROL_PORT) begin
                        if (udp_length == 16'd20 && ip_total_length == 16'd40 &&
                            frame_length >= 11'd54) begin
                            saved_mac     <= source_mac;
                            saved_ip      <= source_ip;
                            saved_port    <= udp_source_port;
                            payload_index <= 0;
                            state         <= READ_PAYLOAD;
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
                        if (payload[0] == "M" && payload[1] == "5" &&
                            payload[2] == "C" && payload[3] == "T" &&
                            payload[4] == 8'd1 &&
                            (payload[5] == 8'd1 || payload[5] == 8'd2 ||
                             payload[5] == 8'd3) &&
                            payload[6] <= 8'd1 && payload[7] == 8'd0) begin
                            command_valid       <= 1'b1;
                            command_opcode      <= payload[5];
                            command_stream_id   <= payload[6][0];
                            command_frame_count <= {payload[8], payload[9], payload[10], read_data};
                            command_source_mac  <= saved_mac;
                            command_source_ip   <= saved_ip;
                            command_source_port <= saved_port;

                            if (payload[5] == 8'd1) begin
                                session_active      <= 1'b1;
                                session_stream_id   <= payload[6][0];
                                session_frame_count <= {payload[8], payload[9], payload[10], read_data};
                                session_host_mac    <= saved_mac;
                                session_host_ip     <= saved_ip;
                                session_host_port   <= saved_port;
                                session_restart     <= 1'b1;
                            end else if (payload[5] == 8'd2) begin
                                session_active  <= 1'b0;
                                session_restart <= 1'b1;
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
