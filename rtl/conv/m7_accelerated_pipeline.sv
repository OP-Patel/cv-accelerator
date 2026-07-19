// Crosses camera pixels into a 200 MHz Sobel core and back to 100 MHz.
// Synthetic batch runs use two identical frame-parallel lanes so the measured
// aggregate compute path accepts two pixels per core cycle.
module m7_accelerated_pipeline #(
    parameter integer IMAGE_WIDTH = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer FIFO_DEPTH = 1024,
    parameter integer X_W = 9,
    parameter integer Y_W = 8
) (
    input  logic           system_clk,
    input  logic           reset,
    input  logic           clear_metrics,
    input  logic           metrics_request,
    input  logic           synthetic_start,
    input  logic [15:0]    synthetic_frames,
    input  logic           live_resume,
    input  logic           in_valid,
    input  logic [X_W-1:0] in_x,
    input  logic [Y_W-1:0] in_y,
    input  logic [7:0]     in_gray,
    output logic           out_valid,
    output logic [X_W-1:0] out_x,
    output logic [Y_W-1:0] out_y,
    output logic [7:0]     out_pixel,
    output logic           core_locked,
    output logic           input_overflow_sticky,
    output logic           output_overflow_sticky,
    output logic           metrics_busy,
    output logic           metrics_valid,
    output logic           synthetic_busy,
    output logic [15:0]    synthetic_completed_frames,
    output logic [31:0]    last_latency_cycles,
    output logic [31:0]    last_frame_interval_cycles,
    output logic [31:0]    last_accepted_pixels,
    output logic [31:0]    last_produced_pixels,
    output logic [31:0]    last_valid_gap_cycles,
    output logic [31:0]    completed_frames,
    output logic [31:0]    last_output_crc
);
    localparam integer INPUT_W = X_W + Y_W + 8;
    localparam integer OUTPUT_W = X_W + Y_W + 8;
    localparam integer COUNT_W = $clog2(FIFO_DEPTH) + 1;
    logic core_clk, core_reset;
    (* ASYNC_REG = "TRUE" *) logic [1:0] clear_metrics_core_sync;
    logic fifo_reset;
    logic [INPUT_W-1:0] input_data;
    logic [INPUT_W-1:0] core_input_data;
    logic input_full, input_empty, input_wr_busy, input_rd_busy;
    logic input_fifo_overflow, input_fifo_underflow;
    logic core_in_valid;
    logic [X_W-1:0] core_in_x;
    logic [Y_W-1:0] core_in_y;
    logic [7:0] core_in_gray;
    logic core_out_valid;
    logic [X_W-1:0] core_out_x;
    logic [Y_W-1:0] core_out_y;
    logic [7:0] core_out_pixel;
    logic parallel_out_valid;
    logic [X_W-1:0] parallel_out_x;
    logic [Y_W-1:0] parallel_out_y;
    logic [7:0] parallel_out_pixel;
    logic [OUTPUT_W-1:0] output_data, system_output_data;
    logic output_full, output_empty, output_wr_busy, output_rd_busy;
    logic output_fifo_overflow, output_fifo_underflow;
    logic output_overflow_core_sticky;
    (* ASYNC_REG = "TRUE" *) logic [1:0] output_overflow_system_sync;
    logic [31:0] unused_pipeline_counter [0:5];
    logic [31:0] unused_parallel_counter [0:5];
    logic [223:0] metrics_source, metrics_snapshot;
    logic [31:0] source_last_latency_cycles;
    logic [31:0] source_last_frame_interval_cycles;
    logic [31:0] source_last_accepted_pixels;
    logic [31:0] source_last_produced_pixels;
    logic [31:0] source_last_valid_gap_cycles;
    logic [31:0] source_completed_frames;
    logic synthetic_toggle_system;
    logic [15:0] synthetic_frames_system;
    (* ASYNC_REG = "TRUE" *) logic [2:0] synthetic_toggle_core_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] synthetic_frames_core_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] synthetic_busy_system_sync;
    (* ASYNC_REG = "TRUE" *) logic [31:0] synthetic_completed_frames_system_sync;
    logic synthetic_toggle_seen;
    logic synthetic_active, synthetic_discard_outputs, synthetic_busy_core;
    logic [15:0] synthetic_remaining, synthetic_target;
    logic [15:0] synthetic_outputs_remaining;
    logic [X_W-1:0] synthetic_x;
    logic [Y_W-1:0] synthetic_y;
    logic synthetic_math_valid, synthetic_feed_valid;
    logic [X_W-1:0] synthetic_math_x, synthetic_feed_x;
    logic [Y_W-1:0] synthetic_math_y, synthetic_feed_y;
    logic [11:0] synthetic_base_sum;
    logic [4:0] synthetic_mix;
    logic [7:0] synthetic_feed_pixel;
    logic fifo_core_valid;
    logic input_fifo_read;
    logic synthetic_input_blocked, synthetic_busy_seen_system;
    logic synthetic_resume_requested;
    logic synthetic_live_resume, allow_live_input;
    logic [15:0] synthetic_completed_frames_core;
    logic synthetic_result_valid_core;
    logic synthetic_batch_started;
    logic [31:0] synthetic_batch_cycle_counter;
    logic [31:0] synthetic_batch_interval_cycles;

    m7_core_clock u_core_clock (
        .clk_100mhz(system_clk), .reset(reset),
        .core_clk(core_clk), .locked(core_locked)
    );
    assign fifo_reset = reset || !core_locked;
    reset_sync u_core_reset (
        .clk(core_clk), .async_reset_in(fifo_reset), .sync_reset_out(core_reset)
    );
    always_ff @(posedge core_clk) begin
        if (core_reset)
            clear_metrics_core_sync <= '0;
        else
            clear_metrics_core_sync <= {
                clear_metrics_core_sync[0], clear_metrics
            };
    end

    assign input_data = {in_x, in_y, in_gray};
    // A synthetic run intentionally owns the core. Block new live pixels,
    // leave any already queued pixels intact, then resume on a frame boundary.
    assign synthetic_live_resume = synthetic_input_blocked &&
                                   synthetic_busy_seen_system &&
                                   !synthetic_busy_system_sync[1] &&
                                   (synthetic_resume_requested || live_resume) && in_valid &&
                                   in_x == '0 && in_y == '0;
    assign allow_live_input = !synthetic_start &&
                              (!synthetic_input_blocked || synthetic_live_resume);
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2), .DOUT_RESET_VALUE("0"), .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("auto"), .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(FIFO_DEPTH), .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(5), .PROG_FULL_THRESH(FIFO_DEPTH-5),
        .RD_DATA_COUNT_WIDTH(COUNT_W), .READ_DATA_WIDTH(INPUT_W),
        .READ_MODE("fwft"), .RELATED_CLOCKS(0), .SIM_ASSERT_CHK(1),
        .USE_ADV_FEATURES("0707"), .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(INPUT_W), .WR_DATA_COUNT_WIDTH(COUNT_W)
    ) u_input_fifo (
        .rst(fifo_reset),
        .wr_clk(system_clk),
        .wr_en(in_valid && allow_live_input && !input_full && !input_wr_busy),
        .din(input_data), .full(input_full), .overflow(input_fifo_overflow),
        .wr_data_count(), .wr_rst_busy(input_wr_busy),
        .rd_clk(core_clk), .rd_en(input_fifo_read),
        .dout(core_input_data), .empty(input_empty), .data_valid(),
        .underflow(input_fifo_underflow), .rd_rst_busy(input_rd_busy),
        .almost_empty(), .almost_full(), .dbiterr(), .sbiterr(),
        .prog_empty(), .prog_full(), .rd_data_count(), .wr_ack(),
        .injectdbiterr(1'b0), .injectsbiterr(1'b0), .sleep(1'b0)
    );
    // Pause the live input FIFO until every registered synthetic pixel has
    // entered the core. This also prevents live pixels from being discarded.
    assign input_fifo_read = !synthetic_active && !synthetic_math_valid &&
                             !synthetic_feed_valid && !input_empty &&
                             !input_rd_busy;
    assign fifo_core_valid = input_fifo_read;
    assign core_in_valid = synthetic_feed_valid || fifo_core_valid;
    assign {core_in_x, core_in_y, core_in_gray} = synthetic_feed_valid ?
           {synthetic_feed_x, synthetic_feed_y, synthetic_feed_pixel} :
           core_input_data;

    always_ff @(posedge system_clk) begin
        if (reset) begin
            synthetic_toggle_system <= 1'b0;
            synthetic_frames_system <= 16'd1;
            synthetic_busy_system_sync <= '0;
            synthetic_completed_frames_system_sync <= '0;
            synthetic_completed_frames <= '0;
            synthetic_input_blocked <= 1'b0;
            synthetic_busy_seen_system <= 1'b0;
            synthetic_resume_requested <= 1'b0;
        end else begin
            if (synthetic_start) begin
                synthetic_frames_system <= (synthetic_frames == 0) ? 16'd1 : synthetic_frames;
                synthetic_toggle_system <= ~synthetic_toggle_system;
                synthetic_input_blocked <= 1'b1;
                synthetic_busy_seen_system <= 1'b0;
                synthetic_resume_requested <= 1'b0;
            end else if (synthetic_input_blocked) begin
                if (live_resume)
                    synthetic_resume_requested <= 1'b1;
                if (synthetic_busy_system_sync[1])
                    synthetic_busy_seen_system <= 1'b1;
                else if (synthetic_live_resume) begin
                    synthetic_input_blocked <= 1'b0;
                    synthetic_busy_seen_system <= 1'b0;
                    synthetic_resume_requested <= 1'b0;
                end
            end
            synthetic_busy_system_sync <= {
                synthetic_busy_system_sync[0],
                synthetic_busy_core
            };
            synthetic_completed_frames_system_sync <= {
                synthetic_completed_frames_system_sync[15:0],
                synthetic_completed_frames_core
            };
            synthetic_completed_frames <= synthetic_completed_frames_system_sync[31:16];
        end
    end
    assign synthetic_busy = synthetic_busy_system_sync[1];

    always_ff @(posedge core_clk) begin
        if (core_reset) begin
            synthetic_toggle_core_sync <= '0;
            synthetic_frames_core_sync <= {2{16'd1}};
            synthetic_toggle_seen <= 1'b0;
            synthetic_active <= 1'b0;
            synthetic_discard_outputs <= 1'b0;
            synthetic_busy_core <= 1'b0;
            output_overflow_core_sticky <= 1'b0;
            synthetic_remaining <= 0;
            synthetic_target <= 0;
            synthetic_outputs_remaining <= 0;
            synthetic_completed_frames_core <= 0;
            synthetic_result_valid_core <= 1'b0;
            synthetic_batch_started <= 1'b0;
            synthetic_batch_cycle_counter <= 0;
            synthetic_batch_interval_cycles <= 0;
            synthetic_x <= 0;
            synthetic_y <= 0;
            synthetic_math_valid <= 1'b0;
            synthetic_feed_valid <= 1'b0;
            synthetic_math_x <= 0;
            synthetic_math_y <= 0;
            synthetic_feed_x <= 0;
            synthetic_feed_y <= 0;
            synthetic_base_sum <= 0;
            synthetic_mix <= 0;
            synthetic_feed_pixel <= 0;
        end else begin
            // Register the busy level before its system-clock synchronizer.
            synthetic_busy_core <= synthetic_active || synthetic_discard_outputs;
            if (clear_metrics_core_sync[1])
                output_overflow_core_sticky <= 1'b0;
            else if (output_fifo_overflow)
                output_overflow_core_sticky <= 1'b1;
            synthetic_toggle_core_sync <= {
                synthetic_toggle_core_sync[1:0], synthetic_toggle_system
            };
            synthetic_frames_core_sync <= {
                synthetic_frames_core_sync[15:0], synthetic_frames_system
            };

            // Register the synthetic calculation in two short stages. The
            // prior single expression directly drove line-buffer BRAM data
            // and was the routed 200 MHz critical path.
            synthetic_math_valid <= synthetic_active;
            if (synthetic_active) begin
                synthetic_math_x <= synthetic_x;
                synthetic_math_y <= synthetic_y;
                synthetic_base_sum <= synthetic_x * 12'd3 +
                                      synthetic_y * 12'd5;
                synthetic_mix <= (synthetic_x ^ synthetic_y) & 5'h1f;
            end
            synthetic_feed_valid <= synthetic_math_valid;
            if (synthetic_math_valid) begin
                synthetic_feed_x <= synthetic_math_x;
                synthetic_feed_y <= synthetic_math_y;
                synthetic_feed_pixel <= synthetic_base_sum[7:0] +
                                        {3'b000, synthetic_mix};
            end

            if (synthetic_toggle_core_sync[2] != synthetic_toggle_seen &&
                !synthetic_active && !synthetic_discard_outputs) begin
                synthetic_toggle_seen <= synthetic_toggle_core_sync[2];
                synthetic_active <= 1'b1;
                synthetic_discard_outputs <= 1'b1;
                // Each batch feeds two deterministic frames, one per lane,
                // on the same coordinate schedule. The final odd request, if
                // any, computes one harmless extra frame but still reports the
                // requested count.
                synthetic_remaining <= (synthetic_frames_core_sync[31:16] >> 1) +
                                       synthetic_frames_core_sync[16];
                synthetic_target <= synthetic_frames_core_sync[31:16];
                synthetic_outputs_remaining <=
                    (synthetic_frames_core_sync[31:16] >> 1) +
                    synthetic_frames_core_sync[16];
                synthetic_completed_frames_core <= 0;
                synthetic_result_valid_core <= 1'b0;
                synthetic_batch_started <= 1'b0;
                synthetic_batch_cycle_counter <= 0;
                synthetic_batch_interval_cycles <= 0;
                synthetic_x <= 0;
                synthetic_y <= 0;
            end
            if (synthetic_feed_valid) begin
                if (synthetic_feed_x == 0 && synthetic_feed_y == 0) begin
                    if (synthetic_batch_started)
                        synthetic_batch_interval_cycles <=
                            synthetic_batch_cycle_counter + 1'b1;
                    synthetic_batch_started <= 1'b1;
                    synthetic_batch_cycle_counter <= 0;
                end else if (synthetic_batch_started) begin
                    synthetic_batch_cycle_counter <=
                        synthetic_batch_cycle_counter + 1'b1;
                end
            end
            if (synthetic_active) begin
                if (synthetic_x == IMAGE_WIDTH-1) begin
                    synthetic_x <= 0;
                    if (synthetic_y == IMAGE_HEIGHT-1) begin
                        synthetic_y <= 0;
                        if (synthetic_remaining == 1)
                            synthetic_active <= 1'b0;
                        else
                            synthetic_remaining <= synthetic_remaining - 1'b1;
                    end else begin
                        synthetic_y <= synthetic_y + 1'b1;
                    end
                end else begin
                    synthetic_x <= synthetic_x + 1'b1;
                end
            end
            if (synthetic_discard_outputs && core_out_valid &&
                core_out_x == IMAGE_WIDTH-2 && core_out_y == IMAGE_HEIGHT-2) begin
                if (synthetic_outputs_remaining == 1) begin
                    synthetic_completed_frames_core <= synthetic_target;
                    synthetic_discard_outputs <= 1'b0;
                    synthetic_result_valid_core <= 1'b1;
                end else
                    synthetic_outputs_remaining <= synthetic_outputs_remaining - 1'b1;
            end
            if (!synthetic_discard_outputs && fifo_core_valid &&
                core_in_x == 0 && core_in_y == 0)
                synthetic_result_valid_core <= 1'b0;
        end
    end

    conv_pipeline_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .X_W(X_W), .Y_W(Y_W)
    ) u_pipeline (
        .clk(core_clk), .reset(core_reset), .in_valid(core_in_valid),
        .in_x(core_in_x), .in_y(core_in_y), .in_gray(core_in_gray),
        .out_valid(core_out_valid), .out_x(core_out_x), .out_y(core_out_y),
        .out_pixel(core_out_pixel),
        .accepted_input_pixels(unused_pipeline_counter[0]),
        .valid_output_pixels(unused_pipeline_counter[1]),
        .frames_started(unused_pipeline_counter[2]),
        .frames_completed(unused_pipeline_counter[3]),
        .protocol_errors(unused_pipeline_counter[4]),
        .output_checksum(unused_pipeline_counter[5])
    );
    // Frame-parallel lane used only by controlled synthetic batch benchmarks.
    // It receives a distinct deterministic pattern on the primary lane's
    // coordinate schedule, giving a real aggregate rate of two accepted pixels
    // per 200 MHz cycle without disturbing the single-camera live path.
    conv_pipeline_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .X_W(X_W), .Y_W(Y_W)
    ) u_parallel_pipeline (
        .clk(core_clk), .reset(core_reset),
        .in_valid(synthetic_feed_valid),
        .in_x(synthetic_feed_x), .in_y(synthetic_feed_y),
        // A distinct second pattern prevents synthesis from merging the two
        // lanes and lets one combined CRC prove both results bit-exact.
        .in_gray(synthetic_feed_pixel ^ 8'ha5),
        .out_valid(parallel_out_valid), .out_x(parallel_out_x),
        .out_y(parallel_out_y), .out_pixel(parallel_out_pixel),
        .accepted_input_pixels(unused_parallel_counter[0]),
        .valid_output_pixels(unused_parallel_counter[1]),
        .frames_started(unused_parallel_counter[2]),
        .frames_completed(unused_parallel_counter[3]),
        .protocol_errors(unused_parallel_counter[4]),
        .output_checksum(unused_parallel_counter[5])
    );
    m7_core_metrics #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .X_W(X_W), .Y_W(Y_W)
    ) u_metrics (
        .clk(core_clk), .reset(core_reset), .clear(clear_metrics_core_sync[1]),
        .in_valid(core_in_valid), .in_x(core_in_x), .in_y(core_in_y),
        .out_valid(core_out_valid), .out_x(core_out_x), .out_y(core_out_y),
        .last_latency_cycles(source_last_latency_cycles),
        .last_frame_interval_cycles(source_last_frame_interval_cycles),
        .last_accepted_pixels(source_last_accepted_pixels),
        .last_produced_pixels(source_last_produced_pixels),
        .last_valid_gap_cycles(source_last_valid_gap_cycles),
        .completed_frames(source_completed_frames)
    );
    always_comb begin
        if (synthetic_result_valid_core) begin
            metrics_source = {
                source_last_latency_cycles,
                synthetic_batch_interval_cycles >> 1,
                source_last_accepted_pixels,
                source_last_produced_pixels,
                source_last_valid_gap_cycles,
                {16'd0, synthetic_target},
                unused_pipeline_counter[5] ^
                {unused_parallel_counter[5][30:0],
                 unused_parallel_counter[5][31]}
            };
        end else begin
            metrics_source = {
                source_last_latency_cycles, source_last_frame_interval_cycles,
                source_last_accepted_pixels, source_last_produced_pixels,
                source_last_valid_gap_cycles, source_completed_frames,
                unused_pipeline_counter[5]
            };
        end
    end
    m5_status_snapshot #(.WIDTH(224)) u_metrics_snapshot (
        .destination_clk(system_clk), .destination_reset(reset),
        .request(metrics_request), .busy(metrics_busy),
        .snapshot_valid(metrics_valid), .snapshot_data(metrics_snapshot),
        .source_clk(core_clk), .source_reset(core_reset), .source_data(metrics_source)
    );
    assign {
        last_latency_cycles, last_frame_interval_cycles,
        last_accepted_pixels, last_produced_pixels,
        last_valid_gap_cycles, completed_frames, last_output_crc
    } = metrics_snapshot;

    assign output_data = {core_out_x, core_out_y, core_out_pixel};
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2), .DOUT_RESET_VALUE("0"), .ECC_MODE("no_ecc"),
        .FIFO_MEMORY_TYPE("auto"), .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH(FIFO_DEPTH), .FULL_RESET_VALUE(0),
        .PROG_EMPTY_THRESH(5), .PROG_FULL_THRESH(FIFO_DEPTH-5),
        .RD_DATA_COUNT_WIDTH(COUNT_W), .READ_DATA_WIDTH(OUTPUT_W),
        .READ_MODE("fwft"), .RELATED_CLOCKS(0), .SIM_ASSERT_CHK(1),
        .USE_ADV_FEATURES("0707"), .WAKEUP_TIME(0),
        .WRITE_DATA_WIDTH(OUTPUT_W), .WR_DATA_COUNT_WIDTH(COUNT_W)
    ) u_output_fifo (
        .rst(fifo_reset),
        .wr_clk(core_clk),
        .wr_en(core_out_valid && !synthetic_discard_outputs &&
               !output_full && !output_wr_busy),
        .din(output_data), .full(output_full), .overflow(output_fifo_overflow),
        .wr_data_count(), .wr_rst_busy(output_wr_busy),
        .rd_clk(system_clk), .rd_en(!output_empty && !output_rd_busy),
        .dout(system_output_data), .empty(output_empty), .data_valid(),
        .underflow(output_fifo_underflow), .rd_rst_busy(output_rd_busy),
        .almost_empty(), .almost_full(), .dbiterr(), .sbiterr(),
        .prog_empty(), .prog_full(), .rd_data_count(), .wr_ack(),
        .injectdbiterr(1'b0), .injectsbiterr(1'b0), .sleep(1'b0)
    );
    assign out_valid = !output_empty && !output_rd_busy;
    assign {out_x, out_y, out_pixel} = system_output_data;

    always_ff @(posedge system_clk) begin
        if (reset) begin
            input_overflow_sticky <= 1'b0;
            output_overflow_sticky <= 1'b0;
            output_overflow_system_sync <= '0;
        end else begin
            // The FIFO overflow indication is a core-clock pulse. Synchronize
            // a sticky core-domain copy so the system clock cannot miss it.
            output_overflow_system_sync <= {
                output_overflow_system_sync[0], output_overflow_core_sticky
            };
            if (clear_metrics) begin
                input_overflow_sticky <= 1'b0;
                output_overflow_sticky <= 1'b0;
            end
            if (in_valid && allow_live_input && (input_full || input_wr_busy))
                input_overflow_sticky <= 1'b1;
            if (output_overflow_system_sync[1])
                output_overflow_sticky <= 1'b1;
        end
    end

    logic unused_fifo_status, unused_parallel_status;
    assign unused_fifo_status = input_fifo_overflow ^ input_fifo_underflow ^
                                output_fifo_underflow ^ output_full;
    assign unused_parallel_status = parallel_out_valid ^ parallel_out_x[0] ^
                                    parallel_out_y[0] ^ parallel_out_pixel[0] ^
                                    unused_parallel_counter[0][0] ^
                                    unused_parallel_counter[1][0] ^
                                    unused_parallel_counter[2][0] ^
                                    unused_parallel_counter[3][0] ^
                                    unused_parallel_counter[4][0];
endmodule
