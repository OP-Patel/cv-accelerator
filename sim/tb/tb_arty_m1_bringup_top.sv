`timescale 1ns/1ps

module tb_arty_m1_bringup_top;
    localparam integer CLOCK_HZ       = 1_000_000;
    localparam integer UART_BAUD      = 100_000;
    localparam integer CLOCKS_PER_BIT = CLOCK_HZ / UART_BAUD;

    logic clk_100mhz = 1'b0;
    logic reset_btn = 1'b1;
    logic [2:0] btn = 3'b000;
    logic [3:0] sw = 4'b0000;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic [3:0] led;

    always #5 clk_100mhz = ~clk_100mhz;

    arty_bringup_top #(
        .CLOCK_HZ(CLOCK_HZ),
        .UART_BAUD(UART_BAUD),
        .DEBOUNCE_CYCLES(2),
        .STATUS_INTERVAL_CYCLES(5_000),
        .HEARTBEAT_BIT(3)
    ) dut (
        .clk_100mhz(clk_100mhz),
        .reset_btn(reset_btn),
        .btn(btn),
        .sw(sw),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led)
    );

    task automatic check(input logic condition, input string description);
        if (!condition) begin
            $error("FAILED: %s (time=%0t, led=%b, uart_tx=%b)",
                   description, $time, led, uart_tx);
            $fatal(1);
        end
    endtask

    task automatic receive_uart_byte(output logic [7:0] received);
        integer bit_number;
        @(negedge uart_tx);
        repeat (CLOCKS_PER_BIT / 2) @(posedge clk_100mhz);
        #1;
        check(uart_tx === 1'b0, "UART activity begins with a low start bit");

        repeat (CLOCKS_PER_BIT) @(posedge clk_100mhz);
        for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
            #1 received[bit_number] = uart_tx;
            repeat (CLOCKS_PER_BIT) @(posedge clk_100mhz);
        end
        #1;
        check(uart_tx === 1'b1, "decoded top-level UART byte has a high stop bit");
    endtask

    logic [7:0] first_byte;

    initial begin
        repeat (4) @(posedge clk_100mhz);
        #1;
        check(led === 4'b0000, "reset forces all LEDs off");
        check(uart_tx === 1'b1, "reset leaves UART idle-high");

        @(negedge clk_100mhz);
        reset_btn = 1'b0;
        repeat (3) @(posedge clk_100mhz);
        #1;
        check(dut.reset_sync === 1'b0, "synchronized reset releases after two clocks");

        fork
            receive_uart_byte(first_byte);
            begin
                repeat (30) @(posedge clk_100mhz);
                #1;
                check(led[0] !== 1'b0, "heartbeat LED changes after reset release");
            end
        join
        check(first_byte == 8'h4D, "first status-message character is ASCII M");

        @(negedge clk_100mhz);
        sw = 4'b0101;
        repeat (6) @(posedge clk_100mhz);
        #1;
        check(led[3:1] === 3'b101, "LEDs 1-3 mirror debounced switches 0-2");

        @(negedge clk_100mhz);
        reset_btn = 1'b1;
        repeat (2) @(posedge clk_100mhz);
        #1;
        check(led === 4'b0000, "asserting reset clears heartbeat and switch LEDs");
        check(uart_tx === 1'b1, "asserting reset aborts UART and restores idle");

        $display("PASS: top-level reset release, LED behavior, switch display, and UART activity verified.");
        $finish;
    end

    initial begin
        #50_000;
        $fatal(1, "FAILED: top-level smoke-test timeout");
    end
endmodule
