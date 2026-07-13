// Connects an OV7670 camera to grayscale, Sobel, counters, LEDs, and UART.
module arty_m3_camera_top #(
    parameter integer CLOCK_HZ        = 100_000_000,
    parameter integer UART_BAUD       = 115_200,
    parameter integer DEBOUNCE_CYCLES = 1_000_000,
    parameter integer IMAGE_WIDTH     = 320,
    parameter integer IMAGE_HEIGHT    = 240,
    parameter integer FIFO_DEPTH      = 1024,
    parameter integer HEARTBEAT_BIT    = 26
) (
    input  logic       clk_100mhz,
    input  logic       reset_btn,
    input  logic [2:0] btn,
    input  logic [3:0] sw,
    input  logic       uart_rx,
    output logic       uart_tx,
    output logic [3:0] led,
    input  logic       cam_pclk,
    input  logic       cam_vsync,
    input  logic       cam_href,
    input  logic [7:0] cam_d,
    output logic       cam_xclk,
    output logic       cam_reset_n,
    output logic       cam_pwdn,
    inout  wire        cam_sio_d,
    output logic       cam_sio_c
);
    localparam integer X_W = $clog2(IMAGE_WIDTH);
    localparam integer Y_W = $clog2(IMAGE_HEIGHT);
    localparam integer ACTIVITY_CYCLES = CLOCK_HZ / 10;
    localparam integer ACTIVITY_W = $clog2(ACTIVITY_CYCLES + 1);

    logic reset, cam_reset;
    logic clock_ready;
    logic [26:0] heartbeat_counter;
    logic [ACTIVITY_W-1:0] activity_count;
    logic restart_clean, restart_delayed, restart_pulse;
    logic clear_errors_clean;
    logic status_clean, status_delayed, status_pulse;
    logic [3:0] sw_clean;
    logic clock_ready_delayed;
    logic init_start;

    logic command_start, command_write, command_busy, command_done;
    logic command_ack_error, command_timeout_error;
    logic [7:0] command_register, command_write_data, command_read_data;
    logic sda_drive_low;
    logic init_busy, init_done, init_error;
    logic init_busy_delayed;
    logic [15:0] completed_writes, nack_count;
    logic [7:0] product_id, version_id;

    (* ASYNC_REG = "TRUE" *) logic [1:0] init_done_cam_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] clear_cam_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] byte_swap_cam_sync;
    logic capture_reset;
    logic cam_pixel_valid, cam_frame_start, cam_frame_end, cam_line_end, cam_byte_seen;
    logic [X_W-1:0] cam_pixel_x;
    logic [Y_W-1:0] cam_pixel_y;
    logic [15:0] cam_pixel_rgb565;
    logic cam_capture_error;
    logic [3:0] cam_capture_flags;

    logic fifo_valid, fifo_frame_start, fifo_frame_end, fifo_line_end;
    logic [X_W-1:0] fifo_x;
    logic [Y_W-1:0] fifo_y;
    logic [15:0] fifo_rgb565;
    logic fifo_overflow;
    logic [31:0] dropped_pixels;
    logic [15:0] maximum_occupancy;

    logic gray_valid, gray_frame_start, gray_frame_end, gray_line_end;
    logic [X_W-1:0] gray_x;
    logic [Y_W-1:0] gray_y;
    logic [7:0] gray_pixel;
    logic [15:0] aligned_rgb565;
    logic coordinate_error;

    logic sobel_valid;
    logic [X_W-1:0] sobel_x;
    logic [Y_W-1:0] sobel_y;
    logic [7:0] sobel_pixel;
    logic [31:0] pipeline_inputs, pipeline_outputs;
    logic [31:0] pipeline_frames_started, pipeline_frames_completed;
    logic [31:0] pipeline_protocol_errors, pipeline_crc;

    (* ASYNC_REG = "TRUE" *) logic [1:0] capture_flags_sync [0:3];
    (* ASYNC_REG = "TRUE" *) logic [1:0] overflow_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] uart_rx_sync;
    logic [15:0] live_error_flags;

    logic snapshot_valid;
    logic [31:0] frame_number, frame_pixel_count, frame_gray_crc;
    logic [31:0] frame_sobel_count, frame_sobel_crc;
    logic [15:0] frame_line_count, frame_errors;

    logic report_pending, report_start;
    logic [7:0] uart_data;
    logic uart_send, uart_busy, reporter_busy;

    reset_sync u_system_reset (
        .clk(clk_100mhz), .async_reset_in(reset_btn), .sync_reset_out(reset)
    );

    camera_xclk u_camera_clock (
        .clk_100mhz(clk_100mhz), .reset(reset),
        .cam_xclk(cam_xclk), .cam_reset_n(cam_reset_n), .cam_pwdn(cam_pwdn),
        .clock_ready(clock_ready)
    );

    // cam_pclk starts only after the camera leaves reset, so assertion is asynchronous.
    reset_sync u_camera_reset (
        .clk(cam_pclk), .async_reset_in(reset_btn || !clock_ready),
        .sync_reset_out(cam_reset)
    );

    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_restart_debounce (
        .clk(clk_100mhz), .reset(reset), .noisy_in(btn[0]), .clean_out(restart_clean)
    );
    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_clear_debounce (
        .clk(clk_100mhz), .reset(reset), .noisy_in(btn[1]), .clean_out(clear_errors_clean)
    );
    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_status_debounce (
        .clk(clk_100mhz), .reset(reset), .noisy_in(btn[2]), .clean_out(status_clean)
    );

    genvar switch_index;
    generate
        for (switch_index = 0; switch_index < 4; switch_index = switch_index + 1) begin : g_switches
            debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_switch_debounce (
                .clk(clk_100mhz), .reset(reset), .noisy_in(sw[switch_index]),
                .clean_out(sw_clean[switch_index])
            );
        end
    endgenerate

    assign restart_pulse = restart_clean && !restart_delayed;
    assign status_pulse  = status_clean && !status_delayed;
    assign init_start    = restart_pulse || (clock_ready && !clock_ready_delayed);

    sccb_master #(.CLOCK_HZ(CLOCK_HZ)) u_sccb (
        .clk(clk_100mhz), .reset(reset), .start(command_start),
        .write_enable(command_write), .register_address(command_register),
        .write_data(command_write_data), .read_data(command_read_data),
        .busy(command_busy), .done(command_done),
        .ack_error(command_ack_error), .timeout_error(command_timeout_error),
        .sio_c(cam_sio_c), .sio_d_in(cam_sio_d), .sio_d_drive_low(sda_drive_low)
    );
    assign cam_sio_d = sda_drive_low ? 1'b0 : 1'bz;

    camera_register_init #(.CLOCK_HZ(CLOCK_HZ)) u_camera_init (
        .clk(clk_100mhz), .reset(reset), .start(init_start),
        .test_pattern_enable(sw_clean[0]),
        .command_start(command_start), .command_write_enable(command_write),
        .command_register(command_register), .command_write_data(command_write_data),
        .command_read_data(command_read_data), .command_busy(command_busy),
        .command_done(command_done), .command_ack_error(command_ack_error),
        .command_timeout_error(command_timeout_error),
        .init_busy(init_busy), .init_done(init_done), .init_error(init_error),
        .completed_writes(completed_writes), .nack_count(nack_count),
        .product_id(product_id), .version_id(version_id)
    );

    // Static controls and sticky status are safe to synchronize bit by bit.
    always_ff @(posedge cam_pclk or posedge reset_btn) begin
        if (reset_btn) begin
            init_done_cam_sync <= '0;
            clear_cam_sync     <= '0;
            byte_swap_cam_sync <= '0;
        end else begin
            init_done_cam_sync <= {init_done_cam_sync[0], init_done};
            clear_cam_sync     <= {clear_cam_sync[0], clear_errors_clean};
            byte_swap_cam_sync <= {byte_swap_cam_sync[0], sw_clean[2]};
        end
    end
    assign capture_reset = cam_reset || !init_done_cam_sync[1];

    dvp_rgb565_capture #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_capture (
        .cam_pclk(cam_pclk), .reset(capture_reset),
        .clear_errors(clear_cam_sync[1]),
        .cam_vsync(cam_vsync), .cam_href(cam_href), .cam_d(cam_d),
        .byte_swap(byte_swap_cam_sync[1]),
        .pixel_valid(cam_pixel_valid), .pixel_x(cam_pixel_x), .pixel_y(cam_pixel_y),
        .pixel_rgb565(cam_pixel_rgb565), .frame_start(cam_frame_start),
        .frame_end(cam_frame_end), .line_end(cam_line_end), .byte_seen(cam_byte_seen),
        .capture_error(cam_capture_error), .error_flags(cam_capture_flags)
    );

    camera_stream_cdc #(.FIFO_DEPTH(FIFO_DEPTH), .X_W(X_W), .Y_W(Y_W)) u_cdc (
        .reset(reset_btn),
        .write_clk(cam_pclk), .clear_write_errors(clear_cam_sync[1]),
        .write_valid(cam_pixel_valid), .write_x(cam_pixel_x), .write_y(cam_pixel_y),
        .write_rgb565(cam_pixel_rgb565), .write_frame_start(cam_frame_start),
        .write_frame_end(cam_frame_end), .write_line_end(cam_line_end),
        .read_clk(clk_100mhz), .read_valid(fifo_valid), .read_x(fifo_x), .read_y(fifo_y),
        .read_rgb565(fifo_rgb565), .read_frame_start(fifo_frame_start),
        .read_frame_end(fifo_frame_end), .read_line_end(fifo_line_end),
        .overflow_sticky(fifo_overflow), .dropped_pixels(dropped_pixels),
        .maximum_occupancy(maximum_occupancy)
    );

    camera_stream_adapter #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_adapter (
        .clk(clk_100mhz), .reset(reset), .clear_errors(clear_errors_clean),
        .fifo_valid(fifo_valid), .fifo_x(fifo_x), .fifo_y(fifo_y),
        .fifo_rgb565(fifo_rgb565), .fifo_frame_start(fifo_frame_start),
        .fifo_frame_end(fifo_frame_end), .fifo_line_end(fifo_line_end),
        .in_valid(gray_valid), .in_x(gray_x), .in_y(gray_y), .in_gray(gray_pixel),
        .in_rgb565(aligned_rgb565), .frame_start(gray_frame_start),
        .frame_end(gray_frame_end), .line_end(gray_line_end),
        .coordinate_error(coordinate_error)
    );

    conv_pipeline_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_pipeline (
        .clk(clk_100mhz), .reset(reset),
        .in_valid(gray_valid && !sw_clean[1]), .in_x(gray_x), .in_y(gray_y),
        .in_gray(gray_pixel), .out_valid(sobel_valid), .out_x(sobel_x),
        .out_y(sobel_y), .out_pixel(sobel_pixel),
        .accepted_input_pixels(pipeline_inputs), .valid_output_pixels(pipeline_outputs),
        .frames_started(pipeline_frames_started), .frames_completed(pipeline_frames_completed),
        .protocol_errors(pipeline_protocol_errors), .output_checksum(pipeline_crc)
    );

    generate
        for (switch_index = 0; switch_index < 4; switch_index = switch_index + 1) begin : g_error_sync
            always_ff @(posedge clk_100mhz) begin
                capture_flags_sync[switch_index] <= {
                    capture_flags_sync[switch_index][0], cam_capture_flags[switch_index]
                };
            end
        end
    endgenerate

    always_comb begin
        live_error_flags = '0;
        live_error_flags[0] = init_error || command_ack_error || command_timeout_error;
        live_error_flags[1] = init_error && ({product_id, version_id} != 16'h7670);
        live_error_flags[2] = capture_flags_sync[0][1];
        live_error_flags[3] = capture_flags_sync[1][1];
        live_error_flags[4] = capture_flags_sync[2][1];
        live_error_flags[5] = overflow_sync[1];
        live_error_flags[7] = capture_flags_sync[3][1] || coordinate_error;
        live_error_flags[8] = (pipeline_protocol_errors != 0);
    end

    camera_debug_counters #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_debug_counters (
        .clk(clk_100mhz), .reset(reset),
        .pixel_valid(gray_valid), .pixel_gray(gray_pixel),
        .pixel_frame_start(gray_frame_start),
        .pixel_frame_end(gray_frame_end), .pixel_line_end(gray_line_end),
        .raw_mode(sw_clean[1]),
        .sobel_valid(sobel_valid), .sobel_x(sobel_x), .sobel_y(sobel_y),
        .sobel_pixel(sobel_pixel), .live_error_flags(live_error_flags),
        .freeze_snapshot(sw_clean[3]), .snapshot_valid(snapshot_valid),
        .frame_number(frame_number), .line_count(frame_line_count),
        .pixel_count(frame_pixel_count), .gray_crc(frame_gray_crc),
        .sobel_count(frame_sobel_count), .sobel_crc(frame_sobel_crc),
        .error_flags(frame_errors)
    );

    uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(UART_BAUD)) u_uart_tx (
        .clk(clk_100mhz), .reset(reset), .data(uart_data), .send(uart_send),
        .tx(uart_tx), .busy(uart_busy)
    );

    m3_uart_reporter u_reporter (
        .clk(clk_100mhz), .reset(reset), .start(report_start),
        .chip_id({product_id, version_id}), .config_pass(init_done && !init_error),
        .completed_writes(completed_writes), .nack_count(nack_count),
        .frame_number(frame_number), .line_count(frame_line_count),
        .pixel_count(frame_pixel_count), .gray_crc(frame_gray_crc),
        .sobel_count(frame_sobel_count), .sobel_crc(frame_sobel_crc),
        .error_flags(frame_errors | live_error_flags),
        .uart_data(uart_data), .uart_send(uart_send), .uart_busy(uart_busy),
        .busy(reporter_busy)
    );

    always_ff @(posedge clk_100mhz) begin
        if (reset) begin
            heartbeat_counter  <= '0;
            activity_count     <= '0;
            restart_delayed    <= 1'b0;
            status_delayed     <= 1'b0;
            clock_ready_delayed <= 1'b0;
            init_busy_delayed  <= 1'b0;
            report_pending     <= 1'b0;
            report_start       <= 1'b0;
            overflow_sync      <= '0;
            uart_rx_sync       <= 2'b11;
        end else begin
            heartbeat_counter   <= heartbeat_counter + 1'b1;
            overflow_sync       <= {overflow_sync[0], fifo_overflow};
            uart_rx_sync        <= {uart_rx_sync[0], uart_rx};
            restart_delayed     <= restart_clean;
            status_delayed      <= status_clean;
            clock_ready_delayed <= clock_ready;
            init_busy_delayed   <= init_busy;
            report_start        <= 1'b0;

            if (activity_count != 0) activity_count <= activity_count - 1'b1;
            if (snapshot_valid) activity_count <= ACTIVITY_CYCLES;

            if (snapshot_valid || status_pulse || (init_busy_delayed && !init_busy)) begin
                report_pending <= 1'b1;
            end else if (report_pending && !reporter_busy) begin
                report_pending <= 1'b0;
                report_start   <= 1'b1;
            end
        end
    end

    assign led = reset ? 4'b0000 : {
        |live_error_flags,
        activity_count != 0,
        init_done && !init_error,
        heartbeat_counter[HEARTBEAT_BIT]
    };

    // Keep useful debug-only values visible to synthesis and ILA insertion.
    logic unused_debug;
    assign unused_debug = cam_byte_seen ^ cam_capture_error ^ aligned_rgb565[0] ^
                          dropped_pixels[0] ^ maximum_occupancy[0] ^ pipeline_inputs[0] ^
                          pipeline_outputs[0] ^ pipeline_frames_started[0] ^
                          pipeline_frames_completed[0] ^ pipeline_crc[0] ^ uart_rx_sync[1];
endmodule
