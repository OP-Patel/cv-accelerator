// Locates the SFD, stores a complete frame, validates FCS/length, and parses headers.
module ethernet_frame_rx #(
    parameter integer MAX_FRAME_BYTES = 1522
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        clear_errors,
    input  logic [7:0]  byte_data,
    input  logic        byte_valid,
    input  logic        frame_start,
    input  logic        frame_end,
    input  logic        mii_rx_error,
    input  logic        odd_nibble,
    input  logic [10:0] read_address,
    output logic [7:0]  read_data,
    output logic        frame_done,
    output logic        frame_valid,
    output logic [10:0] frame_length,
    output logic [47:0] destination_mac,
    output logic [47:0] source_mac,
    output logic [15:0] ether_type,
    output logic [31:0] source_ip,
    output logic [31:0] destination_ip,
    output logic [15:0] arp_opcode,
    output logic [15:0] udp_source_port,
    output logic [15:0] udp_destination_port,
    output logic [15:0] udp_length,
    output logic [15:0] ip_total_length,
    output logic [7:0]  ip_protocol,
    output logic        ipv4_checksum_valid,
    output logic [31:0] good_frames,
    output logic [31:0] bad_fcs_frames,
    output logic [31:0] runt_frames,
    output logic [31:0] oversize_frames,
    output logic [31:0] rx_error_frames,
    output logic [31:0] protocol_error_frames,
    output logic [31:0] sequence_gap_frames
);
    logic [7:0] memory [0:MAX_FRAME_BYTES+3];
    logic [10:0] stored_count;
    logic [3:0] preamble_count;
    logic in_payload, overflow_seen;
    logic [31:0] crc_state;
    logic [31:0] ip_checksum_sum;
    logic [31:0] raw_payload_crc, raw_received_crc;
    logic [31:0] raw_sequence, previous_raw_sequence;
    logic seen_raw_sequence, raw_format_ok;
    integer checksum_index;

    function automatic logic [31:0] next_crc32(input logic [31:0] crc, input logic [7:0] value);
        logic [31:0] c; integer i;
        begin
            c = crc;
            for (i = 0; i < 8; i = i + 1)
                c = (c >> 1) ^ ((c[0] ^ value[i]) ? 32'hEDB88320 : 32'h0);
            next_crc32 = c;
        end
    endfunction

    assign read_data = memory[read_address];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            stored_count <= '0; preamble_count <= '0; in_payload <= 1'b0;
            overflow_seen <= 1'b0; crc_state <= 32'hFFFF_FFFF;
            frame_done <= 1'b0; frame_valid <= 1'b0; frame_length <= '0;
            destination_mac <= '0; source_mac <= '0; ether_type <= '0;
            source_ip <= '0; destination_ip <= '0; arp_opcode <= '0;
            udp_source_port <= '0; udp_destination_port <= '0; udp_length <= '0;
            ip_total_length <= '0;
            ip_protocol <= '0; ipv4_checksum_valid <= 1'b0;
            good_frames <= '0; bad_fcs_frames <= '0; runt_frames <= '0;
            oversize_frames <= '0; rx_error_frames <= '0;
            protocol_error_frames <= '0; sequence_gap_frames <= '0;
            previous_raw_sequence <= '0; seen_raw_sequence <= 1'b0;
            raw_sequence <= '0; raw_payload_crc <= 32'hFFFF_FFFF;
            raw_received_crc <= '0; raw_format_ok <= 1'b1;
        end else begin
            frame_done <= 1'b0;
            if (clear_errors) begin
                good_frames <= '0; bad_fcs_frames <= '0; runt_frames <= '0;
                oversize_frames <= '0; rx_error_frames <= '0;
                protocol_error_frames <= '0; sequence_gap_frames <= '0;
                seen_raw_sequence <= 1'b0;
            end
            if (frame_start) begin
                stored_count <= '0; preamble_count <= '0; in_payload <= 1'b0;
                overflow_seen <= 1'b0; crc_state <= 32'hFFFF_FFFF;
                raw_sequence <= '0; raw_payload_crc <= 32'hFFFF_FFFF;
                raw_received_crc <= '0; raw_format_ok <= 1'b1;
            end
            if (byte_valid) begin
                if (!in_payload) begin
                    if (byte_data == 8'h55 && preamble_count < 7) preamble_count <= preamble_count + 1'b1;
                    else if (byte_data == 8'hD5 && preamble_count >= 1) begin in_payload <= 1'b1; stored_count <= '0; crc_state <= 32'hFFFF_FFFF; end
                    else preamble_count <= (byte_data == 8'h55) ? 1 : 0;
                end else begin
                    crc_state <= next_crc32(crc_state, byte_data);
                    if (stored_count < MAX_FRAME_BYTES + 4) begin
                        memory[stored_count] <= byte_data;
                        if (stored_count >= 14 && stored_count < 56)
                            raw_payload_crc <= next_crc32(raw_payload_crc, byte_data);
                        case (stored_count)
                            14: if (byte_data != "M") raw_format_ok <= 1'b0;
                            15: if (byte_data != "4") raw_format_ok <= 1'b0;
                            16: if (byte_data != "T") raw_format_ok <= 1'b0;
                            17: if (byte_data != "E") raw_format_ok <= 1'b0;
                            18: if (byte_data != "S") raw_format_ok <= 1'b0;
                            19: if (byte_data != "T") raw_format_ok <= 1'b0;
                            20,21,22,23: raw_sequence[31-((stored_count-20)*8) -: 8] <= byte_data;
                            24: if (byte_data != 8'h00) raw_format_ok <= 1'b0;
                            25: if (byte_data != 8'd30) raw_format_ok <= 1'b0;
                            56: raw_received_crc[7:0] <= byte_data;
                            57: raw_received_crc[15:8] <= byte_data;
                            58: raw_received_crc[23:16] <= byte_data;
                            59: raw_received_crc[31:24] <= byte_data;
                            default: if (stored_count >= 26 && stored_count < 56 &&
                                         byte_data != ((stored_count-26)^raw_sequence[7:0]))
                                         raw_format_ok <= 1'b0;
                        endcase
                        stored_count <= stored_count + 1'b1;
                    end else overflow_seen <= 1'b1;
                end
            end
            if (frame_end) begin
                frame_done <= 1'b1;
                frame_valid <= 1'b0;
                ipv4_checksum_valid <= 1'b0;
                if (mii_rx_error || odd_nibble) rx_error_frames <= rx_error_frames + 1'b1;
                else if (!in_payload || stored_count < 64) runt_frames <= runt_frames + 1'b1;
                else if (overflow_seen || stored_count > MAX_FRAME_BYTES + 4) oversize_frames <= oversize_frames + 1'b1;
                else if (crc_state != 32'hDEBB20E3) bad_fcs_frames <= bad_fcs_frames + 1'b1;
                else begin
                    frame_valid <= 1'b1;
                    frame_length <= stored_count - 4;
                    destination_mac <= {memory[0],memory[1],memory[2],memory[3],memory[4],memory[5]};
                    source_mac <= {memory[6],memory[7],memory[8],memory[9],memory[10],memory[11]};
                    ether_type <= {memory[12],memory[13]};
                    arp_opcode <= {memory[20],memory[21]};
                    udp_source_port <= {memory[34],memory[35]};
                    udp_destination_port <= {memory[36],memory[37]};
                    udp_length <= {memory[38],memory[39]};
                    ip_total_length <= {memory[16],memory[17]};
                    ip_protocol <= memory[23];
                    if ({memory[12],memory[13]} == 16'h0806) begin
                        source_ip <= {memory[28],memory[29],memory[30],memory[31]};
                        destination_ip <= {memory[38],memory[39],memory[40],memory[41]};
                    end else begin
                        source_ip <= {memory[26],memory[27],memory[28],memory[29]};
                        destination_ip <= {memory[30],memory[31],memory[32],memory[33]};
                    end
                    // One's-complement sum over the fixed 20-byte IPv4 header.
                    ip_checksum_sum = 0;
                    for (checksum_index = 14; checksum_index < 34; checksum_index = checksum_index + 2)
                        ip_checksum_sum = ip_checksum_sum + {memory[checksum_index], memory[checksum_index+1]};
                    ip_checksum_sum = (ip_checksum_sum & 16'hFFFF) + (ip_checksum_sum >> 16);
                    ip_checksum_sum = (ip_checksum_sum & 16'hFFFF) + (ip_checksum_sum >> 16);
                    ipv4_checksum_valid <= (ip_checksum_sum[15:0] == 16'hFFFF) && (memory[14] == 8'h45);
                    if ({memory[12],memory[13]} == 16'h88B5) begin
                        if (!raw_format_ok || (stored_count-4!=60) ||
                            (raw_received_crc != ~raw_payload_crc))
                            protocol_error_frames <= protocol_error_frames + 1'b1;
                        else begin
                            if (seen_raw_sequence && raw_sequence != previous_raw_sequence + 1'b1)
                                sequence_gap_frames <= sequence_gap_frames + 1'b1;
                            previous_raw_sequence <= raw_sequence;
                            seen_raw_sequence <= 1'b1;
                        end
                    end
                    good_frames <= good_frames + 1'b1;
                end
            end
        end
    end
endmodule
