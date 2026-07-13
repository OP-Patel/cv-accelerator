// Crosses complete camera pixel records through a Xilinx asynchronous FIFO.
module camera_stream_cdc #(
    parameter integer FIFO_DEPTH = 1024,
    parameter integer X_W = 9,
    parameter integer Y_W = 8
) (
    input  logic           reset,
    input  logic           write_clk,
    input  logic           clear_write_errors,
    input  logic           write_valid,
    input  logic [X_W-1:0] write_x,
    input  logic [Y_W-1:0] write_y,
    input  logic [15:0]    write_rgb565,
    input  logic           write_frame_start,
    input  logic           write_frame_end,
    input  logic           write_line_end,
    input  logic           read_clk,
    output logic           read_valid,
    output logic [X_W-1:0] read_x,
    output logic [Y_W-1:0] read_y,
    output logic [15:0]    read_rgb565,
    output logic           read_frame_start,
    output logic           read_frame_end,
    output logic           read_line_end,
    output logic           overflow_sticky,
    output logic [31:0]    dropped_pixels,
    output logic [15:0]    maximum_occupancy
);
    localparam integer DATA_W = 3 + X_W + Y_W + 16;
    localparam integer COUNT_W = $clog2(FIFO_DEPTH) + 1;

    logic [DATA_W-1:0] fifo_input, fifo_output;
    logic fifo_full, fifo_empty;
    logic fifo_write, fifo_read;
    logic fifo_data_valid;
    logic fifo_overflow, fifo_underflow;
    logic [COUNT_W-1:0] write_count;
    logic write_reset_busy, read_reset_busy;

    assign fifo_input = {
        write_frame_start, write_frame_end, write_line_end,
        write_x, write_y, write_rgb565
    };
    assign fifo_write = write_valid && !fifo_full && !write_reset_busy;
    assign fifo_read  = !fifo_empty && !read_reset_busy;

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .DOUT_RESET_VALUE("0"),
        .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(FIFO_DEPTH),
        .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(5),
        .PROG_FULL_THRESH(FIFO_DEPTH - 5),
        .RD_DATA_COUNT_WIDTH(COUNT_W),
        .READ_DATA_WIDTH(DATA_W),
        .READ_MODE("fwft"),
        .RELATED_CLOCKS(0),
        .SIM_ASSERT_CHK(1),
        .USE_ADV_FEATURES("0707"),
        .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(DATA_W),
        .WR_DATA_COUNT_WIDTH(COUNT_W)
    ) u_fifo (
        .rst(reset),
        .wr_clk(write_clk), .wr_en(fifo_write), .din(fifo_input),
        .full(fifo_full), .overflow(fifo_overflow),
        .wr_data_count(write_count), .wr_rst_busy(write_reset_busy),
        .rd_clk(read_clk), .rd_en(fifo_read), .dout(fifo_output),
        .empty(fifo_empty), .data_valid(fifo_data_valid),
        .underflow(fifo_underflow), .rd_rst_busy(read_reset_busy),
        .almost_empty(), .almost_full(), .dbiterr(), .sbiterr(),
        .prog_empty(), .prog_full(), .rd_data_count(), .wr_ack(),
        .injectdbiterr(1'b0), .injectsbiterr(1'b0), .sleep(1'b0)
    );

    always_ff @(posedge write_clk) begin
        if (reset) begin
            overflow_sticky  <= 1'b0;
            dropped_pixels   <= '0;
            maximum_occupancy <= '0;
        end else begin
            if (clear_write_errors) begin
                overflow_sticky <= 1'b0;
                dropped_pixels  <= '0;
            end
            if (write_valid && (fifo_full || write_reset_busy)) begin
                overflow_sticky <= 1'b1;
                dropped_pixels  <= dropped_pixels + 1'b1;
            end
            if (write_count > maximum_occupancy) begin
                maximum_occupancy <= write_count;
            end
        end
    end

    assign read_valid = !fifo_empty && !read_reset_busy;
    assign {
        read_frame_start, read_frame_end, read_line_end,
        read_x, read_y, read_rgb565
    } = fifo_output;

    // These signals are intentionally consumed by the guarded read/write logic.
    logic unused_fifo_status;
    assign unused_fifo_status = fifo_data_valid ^ fifo_overflow ^ fifo_underflow;
endmodule
