// Sends one stable Milestone 3 camera and Sobel status line over UART.
module m3_uart_reporter (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [15:0] chip_id,
    input  logic        config_pass,
    input  logic [15:0] completed_writes,
    input  logic [15:0] nack_count,
    input  logic [31:0] frame_number,
    input  logic [15:0] line_count,
    input  logic [31:0] pixel_count,
    input  logic [31:0] gray_crc,
    input  logic [31:0] sobel_count,
    input  logic [31:0] sobel_crc,
    input  logic [15:0] error_flags,
    output logic [7:0]  uart_data,
    output logic        uart_send,
    input  logic        uart_busy,
    output logic        busy
);
    localparam integer MESSAGE_LENGTH = 119;

    typedef enum logic [1:0] {
        REPORT_IDLE,
        REPORT_SEND,
        REPORT_WAIT_BUSY,
        REPORT_WAIT_DONE
    } report_state_t;

    report_state_t state;
    logic [6:0] character_index;
    logic [15:0] saved_chip_id, saved_writes, saved_nacks, saved_lines, saved_errors;
    logic [31:0] saved_frame, saved_pixels, saved_gray_crc, saved_sobel_count, saved_sobel_crc;
    logic saved_pass;

    // Converts one nibble into an uppercase hexadecimal ASCII character.
    function automatic logic [7:0] hex_character(input logic [3:0] nibble);
        if (nibble < 10) begin
            hex_character = "0" + nibble;
        end else begin
            hex_character = "A" + nibble - 10;
        end
    endfunction

    // Selects one most-significant-first digit from a 16-bit value.
    function automatic logic [7:0] hex16_digit(
        input logic [15:0] value,
        input logic [1:0] digit_index
    );
        hex16_digit = hex_character(value[15 - (digit_index * 4) -: 4]);
    endfunction

    // Selects one most-significant-first digit from a 32-bit value.
    function automatic logic [7:0] hex32_digit(
        input logic [31:0] value,
        input logic [2:0] digit_index
    );
        hex32_digit = hex_character(value[31 - (digit_index * 4) -: 4]);
    endfunction

    // Builds the fixed-width status line documented in the Milestone 3 walkthrough.
    function automatic logic [7:0] report_character(
        input logic [6:0] index,
        input logic [15:0] id_value,
        input logic pass_value,
        input logic [15:0] writes_value,
        input logic [15:0] nacks_value,
        input logic [31:0] frame_value,
        input logic [15:0] lines_value,
        input logic [31:0] pixels_value,
        input logic [31:0] gray_value,
        input logic [31:0] out_value,
        input logic [31:0] sobel_value,
        input logic [15:0] errors_value
    );
        begin
            if ((index >= 6) && (index <= 9)) begin
                report_character = hex16_digit(id_value, index - 6);
            end else if ((index >= 20) && (index <= 23)) begin
                report_character = hex16_digit(writes_value, index - 20);
            end else if ((index >= 30) && (index <= 33)) begin
                report_character = hex16_digit(nacks_value, index - 30);
            end else if ((index >= 37) && (index <= 44)) begin
                report_character = hex32_digit(frame_value, index - 37);
            end else if ((index >= 51) && (index <= 54)) begin
                report_character = hex16_digit(lines_value, index - 51);
            end else if ((index >= 60) && (index <= 67)) begin
                report_character = hex32_digit(pixels_value, index - 60);
            end else if ((index >= 74) && (index <= 81)) begin
                report_character = hex32_digit(gray_value, index - 74);
            end else if ((index >= 87) && (index <= 94)) begin
                report_character = hex32_digit(out_value, index - 87);
            end else if ((index >= 100) && (index <= 107)) begin
                report_character = hex32_digit(sobel_value, index - 100);
            end else if ((index >= 113) && (index <= 116)) begin
                report_character = hex16_digit(errors_value, index - 113);
            end else begin
                case (index)
                    0: report_character = "M";
                    1: report_character = "3";
                    2, 10, 16, 24, 34, 45, 55, 68, 82, 95, 108: report_character = " ";
                    3: report_character = "I";
                    4: report_character = "D";
                    5, 14, 19, 29, 36, 50, 59, 73, 86, 99, 112: report_character = "=";
                    11: report_character = "C";
                    12: report_character = "F";
                    13: report_character = "G";
                    15: report_character = pass_value ? "P" : "F";
                    17: report_character = "W";
                    18: report_character = "R";
                    25: report_character = "N";
                    26: report_character = "A";
                    27: report_character = "C";
                    28: report_character = "K";
                    35: report_character = "F";
                    46: report_character = "L";
                    47: report_character = "I";
                    48: report_character = "N";
                    49: report_character = "E";
                    56: report_character = "P";
                    57: report_character = "I";
                    58: report_character = "X";
                    69: report_character = "G";
                    70: report_character = "R";
                    71: report_character = "A";
                    72: report_character = "Y";
                    83: report_character = "O";
                    84: report_character = "U";
                    85: report_character = "T";
                    96: report_character = "S";
                    97: report_character = "O";
                    98: report_character = "B";
                    109: report_character = "E";
                    110, 111: report_character = "R";
                    117: report_character = 8'h0d;
                    118: report_character = 8'h0a;
                    default: report_character = " ";
                endcase
            end
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state             <= REPORT_IDLE;
            character_index   <= '0;
            saved_chip_id     <= '0;
            saved_pass        <= 1'b0;
            saved_writes      <= '0;
            saved_nacks       <= '0;
            saved_frame       <= '0;
            saved_lines       <= '0;
            saved_pixels      <= '0;
            saved_gray_crc    <= '0;
            saved_sobel_count <= '0;
            saved_sobel_crc   <= '0;
            saved_errors      <= '0;
            uart_data         <= '0;
            uart_send         <= 1'b0;
            busy              <= 1'b0;
        end else begin
            uart_send <= 1'b0;
            case (state)
                REPORT_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        saved_chip_id     <= chip_id;
                        saved_pass        <= config_pass;
                        saved_writes      <= completed_writes;
                        saved_nacks       <= nack_count;
                        saved_frame       <= frame_number;
                        saved_lines       <= line_count;
                        saved_pixels      <= pixel_count;
                        saved_gray_crc    <= gray_crc;
                        saved_sobel_count <= sobel_count;
                        saved_sobel_crc   <= sobel_crc;
                        saved_errors      <= error_flags;
                        character_index   <= '0;
                        uart_data <= report_character(
                            0, chip_id, config_pass, completed_writes, nack_count,
                            frame_number, line_count, pixel_count, gray_crc,
                            sobel_count, sobel_crc, error_flags
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
                    if (uart_busy) state <= REPORT_WAIT_DONE;
                end

                REPORT_WAIT_DONE: begin
                    if (!uart_busy) begin
                        if (character_index == MESSAGE_LENGTH - 1) begin
                            state <= REPORT_IDLE;
                        end else begin
                            character_index <= character_index + 1'b1;
                            uart_data <= report_character(
                                character_index + 1'b1,
                                saved_chip_id, saved_pass, saved_writes, saved_nacks,
                                saved_frame, saved_lines, saved_pixels, saved_gray_crc,
                                saved_sobel_count, saved_sobel_crc, saved_errors
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
