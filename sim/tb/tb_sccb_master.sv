`timescale 1ns/1ps

// Checks OV7670 write/read ordering, ACK, NACK, stop, and timeout behavior.
module tb_sccb_master;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic write_enable = 1'b0;
    logic [7:0] register_address = '0;
    logic [7:0] write_data = '0;
    logic [7:0] read_data;
    logic busy, done, ack_error, timeout_error;
    logic sio_c, master_drive_low;
    logic slave_drive_low = 1'b0;
    tri1 sio_d;

    logic timeout_start = 1'b0;
    logic timeout_busy, timeout_done, timeout_ack_error, timed_out;
    logic timeout_sio_c, timeout_sda_drive;
    logic [7:0] timeout_read_data;

    always #5 clk = ~clk;
    assign sio_d = master_drive_low ? 1'b0 : 1'bz;
    assign sio_d = slave_drive_low ? 1'b0 : 1'bz;

    sccb_master #(
        .CLOCK_HZ(1_000_000), .SCCB_HZ(100_000), .TIMEOUT_CYCLES(2_000)
    ) u_dut (
        .clk(clk), .reset(reset), .start(start), .write_enable(write_enable),
        .register_address(register_address), .write_data(write_data),
        .read_data(read_data), .busy(busy), .done(done), .ack_error(ack_error),
        .timeout_error(timeout_error), .sio_c(sio_c), .sio_d_in(sio_d),
        .sio_d_drive_low(master_drive_low)
    );

    sccb_master #(
        .CLOCK_HZ(1_000_000), .SCCB_HZ(100_000), .TIMEOUT_CYCLES(30)
    ) u_timeout_dut (
        .clk(clk), .reset(reset), .start(timeout_start), .write_enable(1'b1),
        .register_address(8'h12), .write_data(8'h80),
        .read_data(timeout_read_data), .busy(timeout_busy), .done(timeout_done),
        .ack_error(timeout_ack_error), .timeout_error(timed_out),
        .sio_c(timeout_sio_c), .sio_d_in(1'b1),
        .sio_d_drive_low(timeout_sda_drive)
    );

    // Waits for SDA to fall while SCL is high.
    task automatic wait_for_start;
        begin
            do @(negedge sio_d); while (!sio_c);
        end
    endtask

    // Waits for SDA to rise while SCL is high.
    task automatic wait_for_stop;
        begin
            do @(posedge sio_d); while (!sio_c);
        end
    endtask

    // Receives one most-significant-bit-first byte from the master.
    task automatic receive_byte(output logic [7:0] value);
        integer bit_index;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                @(posedge sio_c);
                value[bit_index] = sio_d;
            end
        end
    endtask

    // Pulls SDA low for exactly one SCCB acknowledge clock.
    task automatic acknowledge_byte;
        begin
            @(negedge sio_c);
            slave_drive_low = 1'b1;
            @(posedge sio_c);
            @(negedge sio_c);
            #1 slave_drive_low = 1'b0;
        end
    endtask

    // Drives one read byte and leaves SDA released for the master's final NACK.
    task automatic send_read_byte(input logic [7:0] value);
        integer bit_index;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                slave_drive_low = !value[bit_index];
                @(posedge sio_c);
                if (bit_index != 0) @(negedge sio_c);
            end
            @(negedge sio_c);
            #1 slave_drive_low = 1'b0;
        end
    endtask

    // Emulates one complete three-byte SCCB register write.
    task automatic emulate_write(
        input logic [7:0] expected_register,
        input logic [7:0] expected_data
    );
        logic [7:0] value;
        begin
            wait_for_start();
            receive_byte(value);
            if (value != 8'h42) $fatal(1, "write device byte was %h", value);
            acknowledge_byte();
            receive_byte(value);
            if (value != expected_register) $fatal(1, "write register was %h", value);
            acknowledge_byte();
            receive_byte(value);
            if (value != expected_data) $fatal(1, "write data was %h", value);
            acknowledge_byte();
            wait_for_stop();
        end
    endtask

    // Emulates the address phase, stop, read phase, and returned register byte.
    task automatic emulate_read(
        input logic [7:0] expected_register,
        input logic [7:0] returned_data
    );
        logic [7:0] value;
        begin
            wait_for_start();
            receive_byte(value);
            if (value != 8'h42) $fatal(1, "read address-phase device byte was %h", value);
            acknowledge_byte();
            receive_byte(value);
            if (value != expected_register) $fatal(1, "read register was %h", value);
            acknowledge_byte();
            wait_for_stop();
            wait_for_start();
            receive_byte(value);
            if (value != 8'h43) $fatal(1, "read device byte was %h", value);
            acknowledge_byte();
            send_read_byte(returned_data);
            wait_for_stop();
        end
    endtask

    // Pulses one command into the main SCCB master.
    task automatic issue_command(
        input logic is_write,
        input logic [7:0] register_value,
        input logic [7:0] data_value
    );
        begin
            @(negedge clk);
            write_enable = is_write;
            register_address = register_value;
            write_data = data_value;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;

        fork
            emulate_write(8'h12, 8'h80);
            issue_command(1'b1, 8'h12, 8'h80);
        join
        wait (done);
        if (ack_error || timeout_error) $fatal(1, "valid write reported an error");

        fork
            emulate_read(8'h0a, 8'h76);
            issue_command(1'b0, 8'h0a, 8'h00);
        join
        wait (done);
        if (ack_error || timeout_error || read_data != 8'h76) begin
            $fatal(1, "valid read failed data=%h ack=%b timeout=%b",
                   read_data, ack_error, timeout_error);
        end

        // No slave ACK is driven for this command.
        issue_command(1'b1, 8'h40, 8'hd0);
        wait (done);
        if (!ack_error || timeout_error) $fatal(1, "NACK was not reported correctly");

        @(negedge clk);
        timeout_start = 1'b1;
        @(negedge clk);
        timeout_start = 1'b0;
        wait (timeout_done);
        if (!timed_out) $fatal(1, "short transaction timeout was not reported");

        $display("PASS: tb_sccb_master");
        $finish;
    end
endmodule
