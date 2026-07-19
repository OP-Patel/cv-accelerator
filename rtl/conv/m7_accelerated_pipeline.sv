// Crosses camera pixels into a 200 MHz reference Sobel core and back to 100 MHz.
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
    logic [OUTPUT_W-1:0] output_data, system_output_data;
    logic output_full, output_empty, output_wr_busy, output_rd_busy;
    logic output_fifo_overflow, output_fifo_underflow;
    logic [31:0] unused_pipeline_counter [0:5];
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
    logic synthetic_active, synthetic_discard_outputs;
    logic [15:0] synthetic_remaining, synthetic_target, synthetic_outputs_seen;
    logic [X_W-1:0] synthetic_x;
    logic [Y_W-1:0] synthetic_y;
    logic [7:0] synthetic_pixel;
    logic fifo_core_valid;
    logic [15:0] synthetic_completed_frames_core;

    m7_core_clock u_core_clock (
        .clk_100mhz(system_clk), .reset(reset),
        .core_clk(core_clk), .locked(core_locked)
    );
    assign fifo_reset = reset || !core_locked;
    reset_sync u_core_reset (
        .clk(core_clk), .async_reset_in(fifo_reset), .sync_reset_out(core_reset)
    );

    assign input_data = {in_x, in_y, in_gray};
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
        .wr_clk(system_clk), .wr_en(in_valid && !input_full && !input_wr_busy),
        .din(input_data), .full(input_full), .overflow(input_fifo_overflow),
        .wr_data_count(), .wr_rst_busy(input_wr_busy),
        .rd_clk(core_clk), .rd_en(!input_empty && !input_rd_busy),
        .dout(core_input_data), .empty(input_empty), .data_valid(),
        .underflow(input_fifo_underflow), .rd_rst_busy(input_rd_busy),
        .almost_empty(), .almost_full(), .dbiterr(), .sbiterr(),
        .prog_empty(), .prog_full(), .rd_data_count(), .wr_ack(),
        .injectdbiterr(1'b0), .injectsbiterr(1'b0), .sleep(1'b0)
    );
    assign fifo_core_valid = !input_empty && !input_rd_busy;
    assign synthetic_pixel = (synthetic_x * 3 + synthetic_y * 5 +
                              ((synthetic_x ^ synthetic_y) & 31)) & 8'hff;
    assign core_in_valid = synthetic_active || fifo_core_valid;
    assign {core_in_x, core_in_y, core_in_gray} = synthetic_active ?
           {synthetic_x, synthetic_y, synthetic_pixel} : core_input_data;

    always_ff @(posedge system_clk) begin
        if (reset) begin
            synthetic_toggle_system <= 1'b0;
            synthetic_frames_system <= 16'd1;
            synthetic_busy_system_sync <= '0;
            synthetic_completed_frames_system_sync <= '0;
            synthetic_completed_frames <= '0;
        end else begin
            if (synthetic_start) begin
                synthetic_frames_system <= (synthetic_frames == 0) ? 16'd1 : synthetic_frames;
                synthetic_toggle_system <= ~synthetic_toggle_system;
            end
            synthetic_busy_system_sync <= {
                synthetic_busy_system_sync[0],
                synthetic_active || synthetic_discard_outputs
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
            synthetic_remaining <= 0;
            synthetic_target <= 0;
            synthetic_outputs_seen <= 0;
            synthetic_completed_frames_core <= 0;
            synthetic_x <= 0;
            synthetic_y <= 0;
        end else begin
            synthetic_toggle_core_sync <= {
                synthetic_toggle_core_sync[1:0], synthetic_toggle_system
            };
            synthetic_frames_core_sync <= {
                synthetic_frames_core_sync[15:0], synthetic_frames_system
            };
            if (synthetic_toggle_core_sync[2] != synthetic_toggle_seen &&
                !synthetic_active && !synthetic_discard_outputs) begin
                synthetic_toggle_seen <= synthetic_toggle_core_sync[2];
                synthetic_active <= 1'b1;
                synthetic_discard_outputs <= 1'b1;
                synthetic_remaining <= synthetic_frames_core_sync[31:16];
                synthetic_target <= synthetic_frames_core_sync[31:16];
                synthetic_outputs_seen <= 0;
                synthetic_completed_frames_core <= 0;
                synthetic_x <= 0;
                synthetic_y <= 0;
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
                synthetic_outputs_seen <= synthetic_outputs_seen + 1'b1;
                if (synthetic_outputs_seen + 1'b1 == synthetic_target) begin
                    synthetic_completed_frames_core <= synthetic_target;
                    synthetic_discard_outputs <= 1'b0;
                end
            end
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
    m7_core_metrics #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .X_W(X_W), .Y_W(Y_W)
    ) u_metrics (
        .clk(core_clk), .reset(core_reset), .clear(clear_metrics),
        .in_valid(core_in_valid), .in_x(core_in_x), .in_y(core_in_y),
        .out_valid(core_out_valid), .out_x(core_out_x), .out_y(core_out_y),
        .last_latency_cycles(source_last_latency_cycles),
        .last_frame_interval_cycles(source_last_frame_interval_cycles),
        .last_accepted_pixels(source_last_accepted_pixels),
        .last_produced_pixels(source_last_produced_pixels),
        .last_valid_gap_cycles(source_last_valid_gap_cycles),
        .completed_frames(source_completed_frames)
    );
    assign metrics_source = {
        source_last_latency_cycles, source_last_frame_interval_cycles,
        source_last_accepted_pixels, source_last_produced_pixels,
        source_last_valid_gap_cycles, source_completed_frames,
        unused_pipeline_counter[5]
    };
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
        end else begin
            if (clear_metrics) begin
                input_overflow_sticky <= 1'b0;
                output_overflow_sticky <= 1'b0;
            end
            if (in_valid && (input_full || input_wr_busy))
                input_overflow_sticky <= 1'b1;
            if (output_fifo_overflow)
                output_overflow_sticky <= 1'b1;
        end
    end

    logic unused_fifo_status;
    assign unused_fifo_status = input_fifo_overflow ^ input_fifo_underflow ^
                                output_fifo_underflow ^ output_full;
endmodule
