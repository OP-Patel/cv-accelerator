`timescale 1ns/1ps

// Runs the complete board-demo path and decodes its UART PASS report.
module tb_arty_m2_sobel_top;
    localparam integer CLOCK_HZ = 1_000_000;
    localparam integer UART_BAUD = 100_000;
    localparam integer CLOCKS_PER_BIT = CLOCK_HZ / UART_BAUD;

    logic clk_100mhz = 1'b0;
    logic reset_btn = 1'b1;
    logic [2:0] btn = '0;
    logic [3:0] sw = 4'b0010;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic [3:0] led;
    logic [7:0] received [0:52];
    integer index;

    always #5 clk_100mhz = ~clk_100mhz;

    arty_m2_sobel_top #(
        .CLOCK_HZ(CLOCK_HZ),
        .UART_BAUD(UART_BAUD),
        .DEBOUNCE_CYCLES(2),
        .IMAGE_WIDTH(320),
        .IMAGE_HEIGHT(240),
        .HEARTBEAT_BIT(4)
    ) u_dut (.*);

    // Receives one 8N1 byte by sampling at the center of each data bit.
    task automatic receive_uart_byte(output logic [7:0] value);
        integer bit_index;
        begin
            @(negedge uart_tx);
            repeat (CLOCKS_PER_BIT + CLOCKS_PER_BIT/2) @(posedge clk_100mhz);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx;
                repeat (CLOCKS_PER_BIT) @(posedge clk_100mhz);
            end
            if (!uart_tx) $fatal(1, "UART stop bit was low");
        end
    endtask

    // Checks an inclusive received-character range against an ASCII string packed left-to-right.
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
                    $fatal(1, "UART text mismatch at index %0d: expected=%c actual=%c",
                           first + character, expected_character, received[first + character]);
                end
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk_100mhz);
        reset_btn = 1'b0;
        repeat (5) @(negedge clk_100mhz);
        btn[0] = 1'b1;
        repeat (4) @(negedge clk_100mhz);
        btn[0] = 1'b0;

        for (index = 0; index < 53; index = index + 1) begin
            receive_uart_byte(received[index]);
        end

        check_text(0, 8,  "M2 PAT=2        ");
        check_text(12, 8, "00012C00        ");
        check_text(25, 8, "000127A4        ");
        check_text(38, 8, "18C9D29E        ");
        check_text(47, 4, "PASS            ");
        if (!led[2] || led[3]) $fatal(1, "PASS/error LEDs are incorrect: %b", led);
        $display("PASS: tb_arty_m2_sobel_top decoded hardware-demo CRC PASS report");
        $finish;
    end
endmodule
