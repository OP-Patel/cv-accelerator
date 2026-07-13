`timescale 1ns/1ps

// Checks ordered asynchronous transfer and an explicit FIFO overflow case.
module tb_camera_stream_cdc;
    logic reset = 1'b1;
    logic write_clk = 1'b0;
    logic read_clk = 1'b0;
    logic clear_write_errors = 1'b0;
    logic write_valid = 1'b0;
    logic [2:0] write_x = '0;
    logic [2:0] write_y = '0;
    logic [15:0] write_rgb565 = '0;
    logic write_frame_start = 1'b0, write_frame_end = 1'b0, write_line_end = 1'b0;
    logic read_valid;
    logic [2:0] read_x, read_y;
    logic [15:0] read_rgb565;
    logic read_frame_start, read_frame_end, read_line_end;
    logic overflow_sticky;
    logic [31:0] dropped_pixels;
    logic [15:0] maximum_occupancy;
    integer received = 0;
    integer writes = 0;
    logic check_order = 1'b1;

    always #3 write_clk = ~write_clk;
    always #11 read_clk = ~read_clk;

    camera_stream_cdc #(.FIFO_DEPTH(16), .X_W(3), .Y_W(3)) u_dut (.*);

    always @(posedge read_clk) begin
        if (!reset && read_valid && check_order) begin
            if (read_rgb565 !== (16'h1000 + received)) begin
                $fatal(1, "FIFO order mismatch expected=%h actual=%h",
                       16'h1000 + received, read_rgb565);
            end
            received = received + 1;
        end
    end

    // Writes one complete record on the next write clock.
    task automatic write_record(input integer value);
        begin
            @(negedge write_clk);
            write_valid = 1'b1;
            write_x = value;
            write_y = 0;
            write_rgb565 = 16'h1000 + value;
            write_frame_start = (value == 0);
            write_frame_end = (value == 7);
            write_line_end = (value == 7);
            @(negedge write_clk);
            write_valid = 1'b0;
            writes = writes + 1;
        end
    endtask

    initial begin
        repeat (8) @(posedge write_clk);
        reset = 1'b0;
        wait (!u_dut.write_reset_busy && !u_dut.read_reset_busy);
        repeat (3) @(posedge write_clk);

        for (integer index = 0; index < 8; index = index + 1) begin
            write_record(index);
        end
        wait (received == 8);
        if (overflow_sticky || dropped_pixels != 0) begin
            $fatal(1, "ordered transfer unexpectedly overflowed");
        end
        check_order = 1'b0;

        // Sustained 166 MHz writes exceed 45 MHz reads and must fill this small FIFO.
        for (integer index = 0; index < 48; index = index + 1) begin
            write_record(index & 7);
        end
        repeat (20) @(posedge write_clk);
        if (!overflow_sticky || dropped_pixels == 0) begin
            $fatal(1, "overflow case did not set the sticky flag and drop count");
        end
        if (maximum_occupancy < 15) $fatal(1, "FIFO never approached full occupancy");

        $display("PASS: tb_camera_stream_cdc");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "CDC test timed out received=%0d dropped=%0d full=%b empty=%b valid=%b",
               received, dropped_pixels, u_dut.fifo_full, u_dut.fifo_empty, read_valid);
    end
endmodule
