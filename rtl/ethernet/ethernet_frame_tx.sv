// Adds preamble/SFD, minimum-frame padding, and Ethernet FCS to indexed frame data.
module ethernet_frame_tx #(
    parameter integer MAX_FRAME_BYTES = 1514
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [10:0] frame_length,
    output logic [10:0] frame_data_index,
    input  logic [7:0]  frame_data,
    output logic [7:0]  output_data,
    output logic        output_valid,
    output logic        output_last,
    input  logic        output_ready,
    output logic        busy,
    output logic        done,
    output logic        length_error
);
    typedef enum logic [2:0] {TX_IDLE, TX_PREAMBLE, TX_DATA, TX_PADDING, TX_FCS} state_t;
    state_t state;
    logic [3:0] preamble_index;
    logic [10:0] data_index, saved_length, padded_length;
    logic [1:0] fcs_index;
    logic [31:0] crc_state;

    function automatic logic [31:0] next_crc32(input logic [31:0] crc, input logic [7:0] value);
        logic [31:0] c;
        integer i;
        begin
            c = crc;
            for (i = 0; i < 8; i = i + 1)
                c = (c >> 1) ^ ((c[0] ^ value[i]) ? 32'hEDB88320 : 32'h0);
            next_crc32 = c;
        end
    endfunction

    assign frame_data_index = data_index;
    always_comb begin
        output_data = 8'h00;
        output_valid = 1'b0;
        output_last = 1'b0;
        case (state)
            TX_PREAMBLE: begin output_valid = 1'b1; output_data = (preamble_index == 7) ? 8'hD5 : 8'h55; end
            TX_DATA: begin output_valid = 1'b1; output_data = frame_data; end
            TX_PADDING: begin output_valid = 1'b1; output_data = 8'h00; end
            TX_FCS: begin
                output_valid = 1'b1;
                case (fcs_index)
                    0: output_data = ~crc_state[7:0];
                    1: output_data = ~crc_state[15:8];
                    2: output_data = ~crc_state[23:16];
                    default: output_data = ~crc_state[31:24];
                endcase
                output_last = (fcs_index == 3);
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= TX_IDLE; preamble_index <= '0; data_index <= '0;
            saved_length <= '0; padded_length <= '0; fcs_index <= '0;
            crc_state <= 32'hFFFF_FFFF; busy <= 1'b0; done <= 1'b0;
            length_error <= 1'b0;
        end else begin
            done <= 1'b0;
            if (state == TX_IDLE) begin
                busy <= 1'b0;
                if (start) begin
                    if ((frame_length < 14) || (frame_length > MAX_FRAME_BYTES)) begin
                        length_error <= 1'b1; done <= 1'b1;
                    end else begin
                        length_error <= 1'b0; busy <= 1'b1; preamble_index <= '0;
                        data_index <= '0; saved_length <= frame_length;
                        padded_length <= (frame_length < 60) ? 11'd60 : frame_length;
                        crc_state <= 32'hFFFF_FFFF; state <= TX_PREAMBLE;
                    end
                end
            end else if (output_valid && output_ready) begin
                case (state)
                    TX_PREAMBLE: begin
                        if (preamble_index == 7) state <= TX_DATA;
                        else preamble_index <= preamble_index + 1'b1;
                    end
                    TX_DATA: begin
                        crc_state <= next_crc32(crc_state, frame_data);
                        if (data_index == saved_length - 1) begin
                            if (saved_length < 60) begin data_index <= data_index + 1'b1; state <= TX_PADDING; end
                            else begin fcs_index <= '0; state <= TX_FCS; end
                        end else data_index <= data_index + 1'b1;
                    end
                    TX_PADDING: begin
                        crc_state <= next_crc32(crc_state, 8'h00);
                        data_index <= data_index + 1'b1;
                        if (data_index == padded_length - 1) begin fcs_index <= '0; state <= TX_FCS; end
                    end
                    TX_FCS: begin
                        if (fcs_index == 3) begin state <= TX_IDLE; busy <= 1'b0; done <= 1'b1; end
                        else fcs_index <= fcs_index + 1'b1;
                    end
                    default: state <= TX_IDLE;
                endcase
            end
        end
    end
endmodule
