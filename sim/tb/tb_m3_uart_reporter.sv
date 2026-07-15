`timescale 1ns/1ps

// Decodes the complete fixed-width Milestone 3 status line.
module tb_m3_uart_reporter;
    localparam integer CLOCK_HZ = 1_000_000;
    localparam integer UART_BAUD = 100_000;
    localparam integer CLOCKS_PER_BIT = CLOCK_HZ / UART_BAUD;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic [15:0] chip_id = 16'h7670;
    logic config_pass = 1'b1;
    logic [15:0] completed_writes = 16'h0042;
    logic [15:0] nack_count = 16'h0000;
    logic [31:0] frame_number = 32'h0000002a;
    logic [15:0] line_count = 16'h00f0;
    logic [31:0] pixel_count = 32'h00012c00;
    logic [31:0] gray_crc = 32'h12345678;
    logic [31:0] sobel_count = 32'h000127a4;
    logic [31:0] sobel_crc = 32'h9abcdef0;
    logic [15:0] raw_line_bytes = 16'h0280;
    logic [15:0] raw_frame_lines = 16'h00f0;
    logic [15:0] error_flags = 16'h0000;
    logic [7:0] uart_data;
    logic uart_send, uart_busy, reporter_busy;
    logic uart_line;
    logic [7:0] received [0:138];

    always #5 clk = ~clk;

    uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(UART_BAUD)) transmitter (
        .clk(clk), .reset(reset), .data(uart_data), .send(uart_send),
        .tx(uart_line), .busy(uart_busy)
    );
    m3_uart_reporter reporter (.clk(clk), .reset(reset), .start(start), .busy(reporter_busy), .*);

    // Receives one 8N1 byte at the center of each data bit.
    task automatic receive_uart_byte(output logic [7:0] value);
        integer bit_index;
        begin
            @(negedge uart_line);
            repeat (CLOCKS_PER_BIT + CLOCKS_PER_BIT/2) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_line;
                repeat (CLOCKS_PER_BIT) @(posedge clk);
            end
            if (!uart_line) $fatal(1, "UART stop bit was low");
        end
    endtask

    // Checks a received range against a left-aligned packed ASCII string.
    task automatic check_text(
        input integer first,
        input integer length,
        input logic [8*16-1:0] expected
    );
        integer character;
        logic [7:0] expected_character;
        begin
            for (character = 0; character < length; character = character + 1) begin
                expected_character = expected[8*(16-character)-1 -: 8];
                if (received[first + character] !== expected_character) begin
                    $fatal(1, "text mismatch at %0d expected=%c actual=%c",
                           first + character, expected_character, received[first + character]);
                end
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        for (integer index = 0; index < 139; index = index + 1) begin
            receive_uart_byte(received[index]);
        end

        check_text(0, 10, "M3 ID=7670      ");
        check_text(11, 5, "CFG=P           ");
        check_text(17, 7, "WR=0042         ");
        check_text(25, 9, "NACK=0000       ");
        check_text(35, 10, "F=0000002A      ");
        check_text(46, 9, "LINE=00F0       ");
        check_text(56, 12, "PIX=00012C00    ");
        check_text(69, 13, "GRAY=12345678   ");
        check_text(83, 12, "OUT=000127A4    ");
        check_text(96, 12, "SOB=9ABCDEF0    ");
        check_text(109, 8, "ERR=0000        ");
        check_text(118, 9, "RAWB=0280       ");
        check_text(128, 9, "RAWL=00F0       ");
        if (received[137] != 8'h0d || received[138] != 8'h0a) begin
            $fatal(1, "status line did not end in CRLF");
        end
        $display("PASS: tb_m3_uart_reporter");
        $finish;
    end
endmodule
