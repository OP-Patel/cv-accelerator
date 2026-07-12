// Sends one compact hexadecimal Milestone 2 result line through the existing UART.
module m2_uart_reporter (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [2:0]  pattern,
    input  logic [31:0] input_count,
    input  logic [31:0] output_count,
    input  logic [31:0] checksum,
    input  logic        pass,
    output logic [7:0]  uart_data,
    output logic        uart_send,
    input  logic        uart_busy,
    output logic        busy
);
    localparam integer MESSAGE_LENGTH = 53;

    typedef enum logic [1:0] {
        REPORT_IDLE,
        REPORT_SEND,
        REPORT_WAIT_BUSY,
        REPORT_WAIT_DONE
    } report_state_t;

    report_state_t state;
    logic [5:0] character_index;
    logic [2:0] saved_pattern;
    logic [31:0] saved_input_count;
    logic [31:0] saved_output_count;
    logic [31:0] saved_checksum;
    logic saved_pass;

    // Converts one nibble to an uppercase ASCII hexadecimal character.
    function automatic logic [7:0] hex_character(input logic [3:0] nibble);
        if (nibble < 10) begin
            hex_character = "0" + nibble;
        end else begin
            hex_character = "A" + nibble - 10;
        end
    endfunction

    // Selects a hexadecimal digit from most-significant to least-significant.
    function automatic logic [7:0] hex_digit(
        input logic [31:0] value,
        input logic [2:0] digit_index
    );
        hex_digit = hex_character(value[31 - (digit_index * 4) -: 4]);
    endfunction

    // Builds "M2 PAT=X IN=hhhhhhhh OUT=hhhhhhhh CRC=hhhhhhhh PASS|FAIL".
    function automatic logic [7:0] report_character(
        input logic [5:0] index,
        input logic [2:0] pattern_value,
        input logic [31:0] in_count,
        input logic [31:0] out_count,
        input logic [31:0] crc,
        input logic is_pass
    );
        begin
            if ((index >= 12) && (index <= 19)) begin
                report_character = hex_digit(in_count, index - 12);
            end else if ((index >= 25) && (index <= 32)) begin
                report_character = hex_digit(out_count, index - 25);
            end else if ((index >= 38) && (index <= 45)) begin
                report_character = hex_digit(crc, index - 38);
            end else begin
                case (index)
                    0: report_character = "M";
                    1: report_character = "2";
                    2, 8, 20, 33, 46: report_character = " ";
                    3: report_character = "P";
                    4: report_character = "A";
                    5: report_character = "T";
                    6, 11, 24, 37: report_character = "=";
                    7: report_character = "0" + pattern_value;
                    9: report_character = "I";
                    10: report_character = "N";
                    21: report_character = "O";
                    22: report_character = "U";
                    23: report_character = "T";
                    34: report_character = "C";
                    35: report_character = "R";
                    36: report_character = "C";
                    47: report_character = is_pass ? "P" : "F";
                    48: report_character = "A";
                    49: report_character = is_pass ? "S" : "I";
                    50: report_character = is_pass ? "S" : "L";
                    51: report_character = 8'h0d;
                    52: report_character = 8'h0a;
                    default: report_character = " ";
                endcase
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state              <= REPORT_IDLE;
            character_index    <= '0;
            saved_pattern      <= '0;
            saved_input_count  <= '0;
            saved_output_count <= '0;
            saved_checksum     <= '0;
            saved_pass         <= 1'b0;
            uart_data          <= '0;
            uart_send          <= 1'b0;
            busy               <= 1'b0;
        end else begin
            uart_send <= 1'b0;
            case (state)
                REPORT_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        saved_pattern      <= pattern;
                        saved_input_count  <= input_count;
                        saved_output_count <= output_count;
                        saved_checksum     <= checksum;
                        saved_pass         <= pass;
                        character_index    <= '0;
                        uart_data <= report_character(
                            0, pattern, input_count, output_count, checksum, pass
                        );
                        busy  <= 1'b1;
                        state <= REPORT_SEND;
                    end
                end

                REPORT_SEND: begin
                    uart_send <= 1'b1;
                    state <= REPORT_WAIT_BUSY;
                end

                REPORT_WAIT_BUSY: begin
                    if (uart_busy) begin
                        state <= REPORT_WAIT_DONE;
                    end
                end

                REPORT_WAIT_DONE: begin
                    if (!uart_busy) begin
                        if (character_index == MESSAGE_LENGTH - 1) begin
                            state <= REPORT_IDLE;
                        end else begin
                            character_index <= character_index + 1'b1;
                            uart_data <= report_character(
                                character_index + 1'b1,
                                saved_pattern,
                                saved_input_count,
                                saved_output_count,
                                saved_checksum,
                                saved_pass
                            );
                            state <= REPORT_SEND;
                        end
                    end
                end

                default: state <= REPORT_IDLE;
            endcase
        end
    end
endmodule
