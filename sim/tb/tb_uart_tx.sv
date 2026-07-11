`timescale 1ns/1ps

module tb_uart_tx;
    localparam integer CLOCK_HZ       = 1_000_000;
    localparam integer BAUD_RATE      = 100_000;
    localparam integer CLOCKS_PER_BIT = CLOCK_HZ / BAUD_RATE;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [7:0] data = 8'h00;
    logic send = 1'b0;
    logic tx;
    logic busy;

    integer checked_bits = 0;

    always #5 clk = ~clk;

    uart_tx #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .data(data),
        .send(send),
        .tx(tx),
        .busy(busy)
    );

    task automatic check(input logic condition, input string description);
        if (!condition) begin
            $error("FAILED: %s (time=%0t, tx=%b, busy=%b)",
                   description, $time, tx, busy);
            $fatal(1);
        end
    endtask

    task automatic sample_serial_bit(
        input logic expected,
        input string description
    );
        repeat (CLOCKS_PER_BIT / 2) @(posedge clk);
        #1;
        check(tx === expected, description);
        check(busy === 1'b1, "busy remains high during every frame bit");
        checked_bits = checked_bits + 1;
        repeat (CLOCKS_PER_BIT - (CLOCKS_PER_BIT / 2)) @(posedge clk);
        #1;
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;
        check(tx === 1'b1, "TX is idle-high during reset");
        check(busy === 1'b0, "busy is low during reset");

        @(negedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check(tx === 1'b1, "TX stays idle-high after reset release");
        check(busy === 1'b0, "busy stays low while idle");

        @(negedge clk);
        data = 8'hA5;
        send = 1'b1;
        @(posedge clk);
        #1;
        send = 1'b0;
        check(tx === 1'b0, "send immediately begins the start bit");
        check(busy === 1'b1, "busy rises when a byte is accepted");

        sample_serial_bit(1'b0, "start bit is low");

        // A request made while busy must not replace or corrupt the active byte.
        data = 8'h3C;
        send = 1'b1;
        @(posedge clk);
        #1;
        send = 1'b0;

        sample_serial_bit(1'b1, "data bit 0 of 0xA5");
        sample_serial_bit(1'b0, "data bit 1 of 0xA5");
        sample_serial_bit(1'b1, "data bit 2 of 0xA5");
        sample_serial_bit(1'b0, "data bit 3 of 0xA5");
        sample_serial_bit(1'b0, "data bit 4 of 0xA5");
        sample_serial_bit(1'b1, "data bit 5 of 0xA5");
        sample_serial_bit(1'b0, "data bit 6 of 0xA5");
        sample_serial_bit(1'b1, "data bit 7 of 0xA5");
        sample_serial_bit(1'b1, "stop bit is high");

        check(tx === 1'b1, "TX returns to idle-high after the stop bit");
        check(busy === 1'b0, "busy falls after the complete stop bit");
        check(checked_bits == 10, "exactly ten 8N1 frame bits were checked");

        repeat (2 * CLOCKS_PER_BIT) @(posedge clk);
        #1;
        check(tx === 1'b1, "TX remains idle after completion");
        check(busy === 1'b0, "busy remains low after completion");

        $display("PASS: UART idle, start, 8 data bits, stop, busy, and completion verified.");
        $finish;
    end

    initial begin
        #20_000;
        $fatal(1, "FAILED: UART testbench timeout");
    end
endmodule
