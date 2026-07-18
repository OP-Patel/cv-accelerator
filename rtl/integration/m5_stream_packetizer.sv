// Collects one raster chunk and exposes one complete non-fragmented UDP frame.
module m5_stream_packetizer #(
    parameter integer IMAGE_WIDTH = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer MAX_IMAGE_BYTES = 1024,
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP  = 32'hC0A8_0A02,
    parameter logic [15:0] CONTROL_PORT = 16'd4001
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        clear_errors,
    input  logic        session_active,
    input  logic        session_restart,
    input  logic        session_stream_id,
    input  logic [31:0] requested_frame_count,
    input  logic [47:0] host_mac,
    input  logic [31:0] host_ip,
    input  logic [15:0] host_port,
    input  logic        fifo_valid,
    input  logic        fifo_frame_start,
    input  logic        fifo_frame_end,
    input  logic        fifo_discontinuity,
    input  logic        fifo_stream_id,
    input  logic [7:0]  fifo_pixel,
    output logic        fifo_read_enable,
    output logic        packet_ready,
    input  logic        packet_done,
    input  logic [10:0] frame_index,
    output logic [10:0] frame_length,
    output logic [7:0]  frame_data,
    output logic        stream_complete,
    output logic [31:0] frames_sent,
    output logic [31:0] packets_sent,
    output logic [31:0] bytes_sent,
    output logic [31:0] packet_errors
);
    localparam integer SOBEL_WIDTH = IMAGE_WIDTH - 2;
    localparam integer SOBEL_HEIGHT = IMAGE_HEIGHT - 2;
    localparam integer SOBEL_BYTES = SOBEL_WIDTH * SOBEL_HEIGHT;
    localparam integer GRAY_BYTES = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer SOBEL_PACKETS = (SOBEL_BYTES + MAX_IMAGE_BYTES - 1) / MAX_IMAGE_BYTES;
    localparam integer GRAY_PACKETS = (GRAY_BYTES + MAX_IMAGE_BYTES - 1) / MAX_IMAGE_BYTES;
    localparam integer PAYLOAD_COUNT_W = $clog2(MAX_IMAGE_BYTES + 1);

    logic [7:0] packet_memory [0:MAX_IMAGE_BYTES-1];
    logic [PAYLOAD_COUNT_W-1:0] payload_count;
    logic [31:0] frame_byte_count;
    logic [31:0] payload_crc_state;
    logic [31:0] saved_payload_crc;
    logic [15:0] saved_payload_length;
    logic [15:0] packet_index;
    logic [15:0] total_packets;
    logic [31:0] pixel_offset;
    logic [31:0] frame_sequence;
    logic [31:0] next_frame_sequence;
    logic current_stream_id, current_discontinuity, saved_last;
    logic in_frame;
    logic [47:0] saved_host_mac;
    logic [31:0] saved_host_ip;
    logic [15:0] saved_host_port;
    logic [15:0] saved_width, saved_height;
    logic [15:0] ip_total_length, udp_length, ip_identification;
    logic [31:0] checksum_sum;
    logic [15:0] ip_checksum;
    logic expected_last_pixel;
    logic [31:0] selected_frame_bytes;

    // Advances the reflected Ethernet/ZIP CRC-32 used by the wire contract.
    function automatic logic [31:0] next_crc32(
        input logic [31:0] crc,
        input logic [7:0] value
    );
        logic [31:0] c;
        integer bit_index;
        begin
            c = crc;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                c = (c >> 1) ^ ((c[0] ^ value[bit_index]) ? 32'hEDB88320 : 32'h0);
            next_crc32 = c;
        end
    endfunction

    always_comb begin
        selected_frame_bytes = current_stream_id ? GRAY_BYTES : SOBEL_BYTES;
        expected_last_pixel = (frame_byte_count == selected_frame_bytes - 1);
        fifo_read_enable = fifo_valid &&
                           (!session_active || stream_complete || !packet_ready);

        udp_length       = 16'd40 + saved_payload_length;
        ip_total_length  = 16'd20 + udp_length;
        ip_identification = frame_sequence[15:0] ^ packet_index;
        checksum_sum = 16'h4500 + ip_total_length + ip_identification +
                       16'h4000 + 16'h4011 + FPGA_IP[31:16] + FPGA_IP[15:0] +
                       saved_host_ip[31:16] + saved_host_ip[15:0];
        checksum_sum = (checksum_sum & 16'hFFFF) + (checksum_sum >> 16);
        checksum_sum = (checksum_sum & 16'hFFFF) + (checksum_sum >> 16);
        ip_checksum = ~checksum_sum[15:0];
        frame_length = 11'd74 + saved_payload_length;

        if (frame_index < 6)
            frame_data = saved_host_mac[47-(frame_index*8) -: 8];
        else if (frame_index < 12)
            frame_data = FPGA_MAC[47-((frame_index-6)*8) -: 8];
        else begin
            case (frame_index)
                12: frame_data=8'h08; 13: frame_data=8'h00;
                14: frame_data=8'h45; 15: frame_data=8'h00;
                16: frame_data=ip_total_length[15:8]; 17: frame_data=ip_total_length[7:0];
                18: frame_data=ip_identification[15:8]; 19: frame_data=ip_identification[7:0];
                20: frame_data=8'h40; 21: frame_data=8'h00;
                22: frame_data=8'h40; 23: frame_data=8'h11;
                24: frame_data=ip_checksum[15:8]; 25: frame_data=ip_checksum[7:0];
                26: frame_data=FPGA_IP[31:24]; 27: frame_data=FPGA_IP[23:16];
                28: frame_data=FPGA_IP[15:8]; 29: frame_data=FPGA_IP[7:0];
                30: frame_data=saved_host_ip[31:24]; 31: frame_data=saved_host_ip[23:16];
                32: frame_data=saved_host_ip[15:8]; 33: frame_data=saved_host_ip[7:0];
                34: frame_data=CONTROL_PORT[15:8]; 35: frame_data=CONTROL_PORT[7:0];
                36: frame_data=saved_host_port[15:8]; 37: frame_data=saved_host_port[7:0];
                38: frame_data=udp_length[15:8]; 39: frame_data=udp_length[7:0];
                40,41: frame_data=8'h00;
                42: frame_data="M"; 43: frame_data="5"; 44: frame_data="C"; 45: frame_data="V";
                46: frame_data=8'd1;
                47: frame_data={7'd0,current_stream_id};
                48: frame_data={5'd0,
                                (current_discontinuity && packet_index==0),
                                saved_last, (packet_index==0)};
                49: frame_data=8'd32;
                50: frame_data=frame_sequence[31:24]; 51: frame_data=frame_sequence[23:16];
                52: frame_data=frame_sequence[15:8]; 53: frame_data=frame_sequence[7:0];
                54: frame_data=packet_index[15:8]; 55: frame_data=packet_index[7:0];
                56: frame_data=total_packets[15:8]; 57: frame_data=total_packets[7:0];
                58: frame_data=pixel_offset[31:24]; 59: frame_data=pixel_offset[23:16];
                60: frame_data=pixel_offset[15:8]; 61: frame_data=pixel_offset[7:0];
                62: frame_data=saved_payload_length[15:8];
                63: frame_data=saved_payload_length[7:0];
                64: frame_data=saved_width[15:8]; 65: frame_data=saved_width[7:0];
                66: frame_data=saved_height[15:8]; 67: frame_data=saved_height[7:0];
                68,69: frame_data=8'h00;
                70: frame_data=saved_payload_crc[31:24];
                71: frame_data=saved_payload_crc[23:16];
                72: frame_data=saved_payload_crc[15:8];
                73: frame_data=saved_payload_crc[7:0];
                default: frame_data=packet_memory[frame_index-74];
            endcase
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            payload_count         <= '0;
            frame_byte_count      <= '0;
            payload_crc_state     <= 32'hFFFF_FFFF;
            saved_payload_crc     <= '0;
            saved_payload_length  <= '0;
            packet_index          <= '0;
            total_packets         <= '0;
            pixel_offset          <= '0;
            frame_sequence        <= '0;
            next_frame_sequence   <= '0;
            current_stream_id     <= 1'b0;
            current_discontinuity <= 1'b0;
            saved_last            <= 1'b0;
            in_frame              <= 1'b0;
            packet_ready          <= 1'b0;
            saved_host_mac        <= '0;
            saved_host_ip         <= '0;
            saved_host_port       <= '0;
            saved_width           <= '0;
            saved_height          <= '0;
            stream_complete       <= 1'b0;
            frames_sent           <= '0;
            packets_sent          <= '0;
            bytes_sent            <= '0;
            packet_errors         <= '0;
        end else begin
            if (clear_errors)
                packet_errors <= '0;

            if (!session_active) begin
                payload_count       <= '0;
                payload_crc_state   <= 32'hFFFF_FFFF;
                packet_index        <= '0;
                pixel_offset        <= '0;
                in_frame            <= 1'b0;
                packet_ready        <= 1'b0;
            end else if (session_restart) begin
                payload_count         <= '0;
                payload_crc_state     <= 32'hFFFF_FFFF;
                packet_index          <= '0;
                pixel_offset          <= '0;
                in_frame              <= 1'b0;
                packet_ready          <= 1'b0;
                stream_complete       <= 1'b0;
                frames_sent           <= '0;
                packets_sent          <= '0;
                bytes_sent            <= '0;
                next_frame_sequence   <= '0;
            end else begin
                if (packet_done && packet_ready) begin
                    packet_ready <= 1'b0;
                    packets_sent <= packets_sent + 1'b1;
                    bytes_sent   <= bytes_sent + saved_payload_length;
                    if (saved_last) begin
                        in_frame   <= 1'b0;
                        frames_sent <= frames_sent + 1'b1;
                        if (requested_frame_count != 0 &&
                            frames_sent + 1'b1 >= requested_frame_count)
                            stream_complete <= 1'b1;
                    end else begin
                        packet_index     <= packet_index + 1'b1;
                        pixel_offset     <= pixel_offset + saved_payload_length;
                        payload_count    <= '0;
                        payload_crc_state <= 32'hFFFF_FFFF;
                    end
                end

                if (fifo_valid && fifo_read_enable && !stream_complete) begin
                    if (!in_frame || fifo_frame_start) begin
                        if (in_frame && fifo_frame_start)
                            packet_errors <= packet_errors + 1'b1;
                        if (fifo_frame_start && fifo_stream_id == session_stream_id) begin
                            in_frame              <= 1'b1;
                            packet_ready          <= 1'b0;
                            current_stream_id     <= fifo_stream_id;
                            current_discontinuity <= fifo_discontinuity || in_frame;
                            saved_host_mac        <= host_mac;
                            saved_host_ip         <= host_ip;
                            saved_host_port       <= host_port;
                            saved_width           <= fifo_stream_id ? IMAGE_WIDTH : SOBEL_WIDTH;
                            saved_height          <= fifo_stream_id ? IMAGE_HEIGHT : SOBEL_HEIGHT;
                            total_packets         <= fifo_stream_id ? GRAY_PACKETS : SOBEL_PACKETS;
                            frame_sequence        <= next_frame_sequence;
                            next_frame_sequence   <= next_frame_sequence + 1'b1;
                            packet_index          <= '0;
                            pixel_offset          <= '0;
                            frame_byte_count      <= 32'd1;
                            payload_count         <= 1;
                            payload_crc_state     <= next_crc32(32'hFFFF_FFFF, fifo_pixel);
                            packet_memory[0]      <= fifo_pixel;
                            if (fifo_frame_end) begin
                                packet_errors <= packet_errors + 1'b1;
                                in_frame      <= 1'b0;
                                payload_count <= '0;
                            end
                        end
                    end else if (fifo_stream_id != current_stream_id ||
                                 fifo_frame_end != expected_last_pixel) begin
                        packet_errors     <= packet_errors + 1'b1;
                        in_frame          <= 1'b0;
                        packet_ready      <= 1'b0;
                        payload_count     <= '0;
                        payload_crc_state <= 32'hFFFF_FFFF;
                    end else begin
                        packet_memory[payload_count] <= fifo_pixel;
                        frame_byte_count <= frame_byte_count + 1'b1;
                        if ((payload_count == MAX_IMAGE_BYTES-1) || fifo_frame_end) begin
                            saved_payload_length <= payload_count + 1'b1;
                            saved_payload_crc    <= ~next_crc32(payload_crc_state, fifo_pixel);
                            saved_last           <= fifo_frame_end;
                            packet_ready         <= 1'b1;
                        end else begin
                            payload_count     <= payload_count + 1'b1;
                            payload_crc_state <= next_crc32(payload_crc_state, fifo_pixel);
                        end
                    end
                end
            end
        end
    end
endmodule
