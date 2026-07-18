// Buffers processed pixels without backpressuring the camera pipeline.
module m5_stream_fifo #(
    parameter integer FIFO_DEPTH = 32768
) (
    input  logic        reset,
    input  logic        write_clk,
    input  logic        clear_errors,
    input  logic        stream_enable,
    input  logic        write_valid,
    input  logic        write_frame_start,
    input  logic        write_frame_end,
    input  logic        write_stream_id,
    input  logic [7:0]  write_pixel,
    input  logic        read_clk,
    input  logic        read_enable,
    output logic        read_valid,
    output logic        read_frame_start,
    output logic        read_frame_end,
    output logic        read_discontinuity,
    output logic        read_stream_id,
    output logic [7:0]  read_pixel,
    output logic        overflow_sticky,
    output logic [31:0] dropped_frames,
    output logic [31:0] dropped_pixels,
    output logic [15:0] maximum_occupancy
);
    localparam integer COUNT_W = $clog2(FIFO_DEPTH) + 1;
    logic [11:0] fifo_input, fifo_output;
    logic fifo_full, fifo_empty, fifo_write;
    logic fifo_overflow, fifo_underflow, write_reset_busy, read_reset_busy;
    logic [COUNT_W-1:0] write_count;
    logic discarding_frame, discontinuity_pending, enable_delayed;

    assign fifo_input = {
        discontinuity_pending, write_frame_start, write_frame_end,
        write_stream_id, write_pixel
    };
    assign fifo_write = !reset && stream_enable && write_valid &&
                        (!discarding_frame || write_frame_start) &&
                        !fifo_full && !write_reset_busy;

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2), .DOUT_RESET_VALUE("0"), .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("block"), .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(FIFO_DEPTH), .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(5), .PROG_FULL_THRESH(FIFO_DEPTH-16),
        .RD_DATA_COUNT_WIDTH(COUNT_W), .READ_DATA_WIDTH(12),
        .READ_MODE("fwft"), .RELATED_CLOCKS(0), .SIM_ASSERT_CHK(1),
        .USE_ADV_FEATURES("0707"), .WAKEUP_TIME(0), .WRITE_DATA_WIDTH(12),
        .WR_DATA_COUNT_WIDTH(COUNT_W)
    ) u_fifo (
        .rst(reset),
        .wr_clk(write_clk), .wr_en(fifo_write), .din(fifo_input),
        .full(fifo_full), .overflow(fifo_overflow),
        .wr_data_count(write_count), .wr_rst_busy(write_reset_busy),
        .rd_clk(read_clk), .rd_en(read_enable && read_valid), .dout(fifo_output),
        .empty(fifo_empty), .data_valid(), .underflow(fifo_underflow),
        .rd_rst_busy(read_reset_busy), .almost_empty(), .almost_full(),
        .dbiterr(), .sbiterr(), .prog_empty(), .prog_full(),
        .rd_data_count(), .wr_ack(), .injectdbiterr(1'b0),
        .injectsbiterr(1'b0), .sleep(1'b0)
    );

    always_ff @(posedge write_clk) begin
        if (reset) begin
            overflow_sticky      <= 1'b0;
            dropped_frames       <= '0;
            dropped_pixels       <= '0;
            maximum_occupancy    <= '0;
            discarding_frame     <= 1'b0;
            discontinuity_pending <= 1'b0;
            enable_delayed       <= 1'b0;
        end else begin
            enable_delayed <= stream_enable;
            if (clear_errors) begin
                overflow_sticky <= 1'b0;
                dropped_frames  <= '0;
                dropped_pixels  <= '0;
            end
            if (write_count > maximum_occupancy)
                maximum_occupancy <= write_count;

            if (enable_delayed && !stream_enable) begin
                discarding_frame      <= 1'b0;
                discontinuity_pending <= 1'b1;
            end

            if (stream_enable && write_valid) begin
                if (discarding_frame) begin
                    if (write_frame_start && !fifo_full && !write_reset_busy) begin
                        discarding_frame <= 1'b0;
                        if (discontinuity_pending)
                            discontinuity_pending <= 1'b0;
                    end else begin
                        dropped_pixels <= dropped_pixels + 1'b1;
                    end
                end else if (fifo_full || write_reset_busy) begin
                    overflow_sticky      <= 1'b1;
                    dropped_frames       <= dropped_frames + 1'b1;
                    dropped_pixels       <= dropped_pixels + 1'b1;
                    discarding_frame     <= !write_frame_end;
                    discontinuity_pending <= 1'b1;
                end else if (fifo_write && discontinuity_pending && write_frame_start) begin
                    discontinuity_pending <= 1'b0;
                end
            end
        end
    end

    assign read_valid = !reset && !fifo_empty && !read_reset_busy;
    assign {read_discontinuity, read_frame_start, read_frame_end,
            read_stream_id, read_pixel} = fifo_output;

    logic unused_fifo_status;
    assign unused_fifo_status = fifo_overflow ^ fifo_underflow;
endmodule
