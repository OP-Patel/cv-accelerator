`timescale 1ns/1ps

// Checks identity reads, table order completion, restart, and ID mismatch handling.
module tb_camera_register_init;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic test_pattern_enable = 1'b1;
    logic command_start, command_write_enable;
    logic [7:0] command_register, command_write_data;
    logic [7:0] command_read_data = 8'd0;
    logic command_busy = 1'b0;
    logic command_done = 1'b0;
    logic command_ack_error = 1'b0;
    logic command_timeout_error = 1'b0;
    logic init_busy, init_done, init_error;
    logic [15:0] completed_writes, nack_count;
    logic [7:0] product_id, version_id;
    logic bad_id = 1'b0;
    integer command_count = 0;

    always #5 clk = ~clk;

    camera_register_init #(
        .CLOCK_HZ(100), .RESET_DELAY_CYCLES(3), .SETTLE_CYCLES(4)
    ) u_dut (.*);

    // Emulates a one-cycle command target and returns the two identity bytes.
    always_ff @(posedge clk) begin
        command_done <= 1'b0;
        if (command_start && !command_busy) begin
            command_busy <= 1'b1;
            command_count <= command_count + 1;
            if (!command_write_enable) begin
                if (command_register == 8'h0a) command_read_data <= 8'h76;
                if (command_register == 8'h0b) command_read_data <= bad_id ? 8'h73 : 8'h70;
            end
        end else if (command_busy) begin
            command_busy <= 1'b0;
            command_done <= 1'b1;
        end
    end

    // Pulses the initialization request for one system clock.
    task automatic request_initialization;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;
        request_initialization();
        wait (init_done || init_error);
        @(posedge clk);
        if (!init_done || init_error || {product_id, version_id} != 16'h7670) begin
            $fatal(1, "successful initialization did not complete correctly");
        end
        if (completed_writes != 60 || nack_count != 0) begin
            $fatal(1, "unexpected write/NACK counts writes=%0d nacks=%0d",
                   completed_writes, nack_count);
        end

        bad_id = 1'b1;
        request_initialization();
        wait (init_error && !init_busy);
        if ({product_id, version_id} != 16'h7673 || init_done) begin
            $fatal(1, "ID mismatch was not reported correctly");
        end
        $display("PASS: tb_camera_register_init");
        $finish;
    end
endmodule
