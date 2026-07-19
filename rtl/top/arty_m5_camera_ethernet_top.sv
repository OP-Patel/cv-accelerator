// Integrated OV7670 -> grayscale/Sobel -> UDP design for the Arty A7-100T.
module arty_m5_camera_ethernet_top #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer UART_BAUD = 115_200,
    parameter integer DEBOUNCE_CYCLES = 1_000_000,
    parameter integer PHY_RESET_US = 10_000,
    parameter integer PHY_STARTUP_US = 10_000,
    parameter integer IMAGE_WIDTH = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer CAMERA_FIFO_DEPTH = 1024,
    parameter integer STREAM_FIFO_DEPTH = 32768,
    parameter bit M7_ENABLE = 1'b0,
    parameter logic [1:0] M7_DEFAULT_PROFILE = 2'd0,
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP = 32'hC0A8_0A02,
    parameter logic [15:0] ECHO_PORT = 16'd4000,
    parameter logic [15:0] CONTROL_PORT = 16'd4001
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
    output logic       cam_sio_c,
    input  logic       eth_col,
    input  logic       eth_crs,
    output logic       eth_mdc,
    inout  wire        eth_mdio,
    output logic       eth_ref_clk,
    output logic       eth_rstn,
    input  logic       eth_rx_clk,
    input  logic       eth_rx_dv,
    input  logic [3:0] eth_rxd,
    input  logic       eth_rxerr,
    input  logic       eth_tx_clk,
    output logic       eth_tx_en,
    output logic [3:0] eth_txd
);
    localparam integer X_W = $clog2(IMAGE_WIDTH);
    localparam integer Y_W = $clog2(IMAGE_HEIGHT);
    localparam logic [2:0] SOURCE_ARP = 3'd1;
    localparam logic [2:0] SOURCE_CONTROL = 3'd2;
    localparam logic [2:0] SOURCE_ECHO = 3'd3;
    localparam logic [2:0] SOURCE_CAMERA = 3'd4;

    logic reset;
    logic [26:0] heartbeat;
    logic [2:0] btn_clean, btn_delayed;
    logic [3:0] sw_clean;
    logic restart_pulse, clear_level, clear_pulse, status_pulse;

    // Camera control and capture signals in the 100 MHz and PCLK domains.
    logic camera_clock_ready, camera_reset;
    logic camera_init_start, camera_clock_ready_delayed;
    logic command_start, command_write, command_busy, command_done;
    logic command_ack_error, command_timeout_error;
    logic [7:0] command_register, command_write_data, command_read_data;
    logic camera_sda_drive_low;
    logic camera_init_busy, camera_init_done, camera_init_error;
    logic [15:0] completed_writes, camera_nack_count;
    logic [7:0] camera_product_id, camera_version_id;
    logic [1:0] camera_selected_profile;
    logic camera_timing_readback_valid;
    logic [39:0] camera_timing_readback;
    logic [31:0] camera_frame_period_cycles;
    logic [31:0] camera_frame_pclk_edges, camera_active_bytes;
    logic [15:0] camera_line_pclk_edges, camera_active_lines;
    logic [31:0] camera_source_frame_pclk_edges, camera_source_active_bytes;
    logic [15:0] camera_source_line_pclk_edges, camera_source_active_lines;
    logic [127:0] camera_timing_source_snapshot, camera_timing_snapshot;
    logic camera_timing_snapshot_busy, camera_timing_snapshot_valid;
    logic camera_id_valid;
    (* ASYNC_REG = "TRUE" *) logic [1:0] init_done_camera_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] clear_camera_sync;
    logic capture_reset;
    logic camera_pixel_valid, camera_frame_start, camera_frame_end, camera_line_end;
    logic [X_W-1:0] camera_pixel_x;
    logic [Y_W-1:0] camera_pixel_y;
    logic [15:0] camera_pixel_rgb565;
    logic camera_capture_error, camera_byte_seen;
    logic [3:0] camera_capture_flags;
    logic [15:0] observed_line_bytes, observed_frame_lines;

    logic camera_fifo_valid, camera_fifo_frame_start, camera_fifo_frame_end;
    logic camera_fifo_line_end;
    logic [X_W-1:0] camera_fifo_x;
    logic [Y_W-1:0] camera_fifo_y;
    logic [15:0] camera_fifo_rgb565;
    logic camera_fifo_overflow;
    logic [31:0] camera_dropped_pixels;
    logic [15:0] camera_fifo_maximum;

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
    logic [31:0] pipeline_inputs, pipeline_outputs, pipeline_frames_started;
    logic [31:0] pipeline_frames_completed, pipeline_errors, pipeline_crc;
    logic core_locked, core_input_overflow, core_output_overflow;
    logic core_metrics_busy, core_metrics_valid, core_metrics_request;
    logic [31:0] core_latency_cycles, core_frame_interval_cycles;
    logic [31:0] core_accepted_pixels, core_produced_pixels;
    logic [31:0] core_valid_gap_cycles, core_completed_frames;
    logic [31:0] core_output_crc;
    logic core_synthetic_busy;
    logic [15:0] core_synthetic_completed_frames;
    logic thresholded_valid;
    logic [X_W-1:0] thresholded_x;
    logic [Y_W-1:0] thresholded_y;
    logic [7:0] thresholded_pixel;
    logic active_threshold_enable;
    logic [7:0] active_threshold;
    logic processed_valid;
    logic [X_W-1:0] processed_x;
    logic [Y_W-1:0] processed_y;
    logic [7:0] processed_pixel;
    logic [19:0] metrics_refresh_counter;
    logic camera_timing_snapshot_request;

    // PHY control and Ethernet receive signals.
    logic ethernet_clock_ready, phy_ready, phy_ready_delayed;
    logic mdio_start, mdio_write, mdio_busy, mdio_done;
    logic mdio_ack_error, mdio_timeout, mdio_drive_low;
    logic [4:0] mdio_phy, mdio_register;
    logic [15:0] mdio_write_data, mdio_read_data;
    logic [15:0] phy_id1, phy_id2, bmsr, physts;
    logic identity_valid, link_up, speed_100, full_duplex, discovery_done;
    logic [3:0] phy_errors;
    logic bringup_start;
    (* ASYNC_REG = "TRUE" *) logic [1:0] rx_reset_sync, tx_reset_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] clear_rx_sync, link_rx_sync;
    logic rx_reset, tx_reset;
    logic [7:0] rx_byte;
    logic rx_byte_valid, rx_frame_start, rx_frame_end, rx_error, rx_odd;
    logic [10:0] rx_read_address, rx_frame_length;
    logic [7:0] rx_read_data;
    logic rx_frame_done, rx_frame_valid, rx_ipv4_checksum_valid;
    logic [47:0] rx_destination_mac, rx_source_mac;
    logic [15:0] rx_ether_type, rx_arp_opcode;
    logic [15:0] rx_udp_source_port, rx_udp_destination_port, rx_udp_length;
    logic [15:0] rx_ip_total_length;
    logic [31:0] rx_source_ip, rx_destination_ip;
    logic [7:0] rx_ip_protocol;
    logic [31:0] good_frames, bad_fcs_frames, runt_frames, oversize_frames;
    logic [31:0] rx_error_frames, protocol_error_frames, sequence_gap_frames;

    // Learned session and processed stream FIFO.
    logic control_parser_busy, control_command_valid;
    logic [7:0] control_opcode;
    logic control_stream_id;
    logic [31:0] control_frame_count;
    logic [47:0] control_source_mac;
    logic [31:0] control_source_ip;
    logic [15:0] control_source_port;
    logic session_active, session_stream_id, session_restart;
    logic [31:0] session_frame_count, control_errors;
    logic [7:0] control_version, control_status;
    logic [47:0] session_host_mac;
    logic [31:0] session_host_ip;
    logic [15:0] session_host_port;
    logic [1:0] requested_profile_rx;
    logic requested_threshold_enable_rx;
    logic [7:0] requested_threshold_rx;
    logic configuration_toggle_rx;
    logic [15:0] requested_benchmark_frames_rx;
    logic benchmark_toggle_rx;
    logic [10:0] control_read_address;

    (* ASYNC_REG = "TRUE" *) logic [1:0] session_active_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] session_stream_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] stream_complete_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] sw1_rx_sync;
    logic selected_frame_stream, selected_stream_now, capture_stream_enable;
    (* ASYNC_REG = "TRUE" *) logic [2:0] configuration_toggle_sync;
    (* ASYNC_REG = "TRUE" *) logic [5:0] requested_profile_sync;
    (* ASYNC_REG = "TRUE" *) logic [2:0] requested_threshold_enable_sync;
    (* ASYNC_REG = "TRUE" *) logic [23:0] requested_threshold_sync;
    logic configuration_toggle_seen, camera_reconfigure_pulse;
    logic [1:0] m7_profile_select;
    logic m7_threshold_enable;
    logic [7:0] m7_threshold;
    (* ASYNC_REG = "TRUE" *) logic [2:0] benchmark_toggle_sync;
    (* ASYNC_REG = "TRUE" *) logic [47:0] requested_benchmark_frames_sync;
    logic benchmark_toggle_seen, core_synthetic_start;
    logic [15:0] core_synthetic_frames;
    logic stream_write_valid, stream_write_start, stream_write_end;
    logic [7:0] stream_write_pixel;
    logic stream_fifo_read, stream_fifo_valid, stream_fifo_start, stream_fifo_end;
    logic stream_fifo_discontinuity, stream_fifo_id;
    logic [7:0] stream_fifo_pixel;
    logic stream_fifo_overflow;
    logic [31:0] stream_dropped_frames, stream_dropped_pixels;
    logic [15:0] stream_fifo_maximum;

    // Transmit scheduler, packet generators, and MII bridge.
    logic arp_pending, echo_pending, control_pending;
    logic [47:0] arp_source_mac, echo_source_mac;
    logic [31:0] arp_source_ip, echo_source_ip;
    logic [15:0] echo_source_port, echo_udp_length;
    logic [47:0] ack_source_mac;
    logic [31:0] ack_source_ip, ack_frame_count;
    logic [15:0] ack_source_port;
    logic [7:0] ack_version, ack_opcode, ack_status;
    logic ack_stream_id;
    logic arp_grant, control_grant, echo_grant, camera_grant, test_grant;
    logic [2:0] active_source;
    logic frame_tx_start, frame_tx_busy, frame_tx_done, frame_tx_length_error;
    logic [10:0] frame_tx_index, frame_tx_length;
    logic [7:0] frame_tx_data, arp_data, echo_data, control_ack_data, camera_data;
    logic [10:0] arp_length, echo_length, control_ack_length, camera_length;
    logic [10:0] echo_read_address;
    logic camera_packet_ready, camera_stream_complete;
    logic [31:0] camera_frames_sent, camera_packets_sent, camera_bytes_sent;
    logic [31:0] camera_packet_errors;
    logic [7:0] encoded_data;
    logic encoded_valid, encoded_last;
    logic tx_fifo_full, tx_fifo_empty, tx_fifo_overflow, tx_fifo_underflow;
    logic tx_fifo_read, mii_byte_ready, mii_underrun;
    logic [8:0] tx_fifo_output;

    // UART snapshot and reporting signals.
    localparam integer RX_STATUS_W = 224;
    logic snapshot_busy, snapshot_valid;
    logic [RX_STATUS_W-1:0] rx_status_source, rx_status_snapshot;
    logic [31:0] report_frames, report_packets, report_bytes, report_drops;
    logic [31:0] report_packet_errors, report_control_errors, report_bad_frames;
    logic [31:0] live_bad_frames;
    (* ASYNC_REG = "TRUE" *) logic [1:0] tx_underflow_system_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] mii_underrun_system_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] tx_overflow_system_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] tx_length_system_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] collision_system_sync;
    logic report_pending, report_start, reporter_busy, uart_send, uart_busy;
    logic [7:0] uart_data;
    logic [15:0] combined_errors;

    reset_sync u_system_reset (
        .clk(clk_100mhz), .async_reset_in(reset_btn), .sync_reset_out(reset)
    );

    genvar control_index;
    generate
        for (control_index=0; control_index<3; control_index=control_index+1) begin : g_buttons
            debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_button (
                .clk(clk_100mhz), .reset(reset), .noisy_in(btn[control_index]),
                .clean_out(btn_clean[control_index])
            );
        end
        for (control_index=0; control_index<4; control_index=control_index+1) begin : g_switches
            debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_switch (
                .clk(clk_100mhz), .reset(reset), .noisy_in(sw[control_index]),
                .clean_out(sw_clean[control_index])
            );
        end
    endgenerate
    assign restart_pulse = btn_clean[0] && !btn_delayed[0];
    assign clear_level   = btn_clean[1];
    assign clear_pulse   = btn_clean[1] && !btn_delayed[1];
    assign status_pulse  = btn_clean[2] && !btn_delayed[2];

    // Proven Milestone 3 camera front end.
    camera_xclk u_camera_clock (
        .clk_100mhz(clk_100mhz), .reset(reset), .cam_xclk(cam_xclk),
        .cam_reset_n(cam_reset_n), .cam_pwdn(cam_pwdn),
        .clock_ready(camera_clock_ready)
    );
    reset_sync u_camera_reset (
        .clk(cam_pclk), .async_reset_in(reset_btn || !camera_clock_ready),
        .sync_reset_out(camera_reset)
    );
    assign camera_init_start = restart_pulse || camera_reconfigure_pulse ||
                               (camera_clock_ready && !camera_clock_ready_delayed);
    sccb_master #(.CLOCK_HZ(CLOCK_HZ)) u_sccb (
        .clk(clk_100mhz), .reset(reset), .start(command_start),
        .write_enable(command_write), .register_address(command_register),
        .write_data(command_write_data), .read_data(command_read_data),
        .busy(command_busy), .done(command_done), .ack_error(command_ack_error),
        .timeout_error(command_timeout_error), .sio_c(cam_sio_c),
        .sio_d_in(cam_sio_d), .sio_d_drive_low(camera_sda_drive_low)
    );
    assign cam_sio_d = camera_sda_drive_low ? 1'b0 : 1'bz;
    camera_register_init #(
        .CLOCK_HZ(CLOCK_HZ), .ENABLE_M7_PROFILES(M7_ENABLE)
    ) u_camera_init (
        .clk(clk_100mhz), .reset(reset), .start(camera_init_start),
        .test_pattern_enable(sw_clean[0]),
        .profile_select(M7_ENABLE ? m7_profile_select : 2'd0),
        .command_start(command_start),
        .command_write_enable(command_write), .command_register(command_register),
        .command_write_data(command_write_data), .command_read_data(command_read_data),
        .command_busy(command_busy), .command_done(command_done),
        .command_ack_error(command_ack_error), .command_timeout_error(command_timeout_error),
        .init_busy(camera_init_busy), .init_done(camera_init_done),
        .init_error(camera_init_error), .completed_writes(completed_writes),
        .nack_count(camera_nack_count), .product_id(camera_product_id),
        .version_id(camera_version_id), .selected_profile(camera_selected_profile),
        .timing_readback_valid(camera_timing_readback_valid),
        .timing_readback(camera_timing_readback)
    );
    camera_timing_monitor u_camera_timing (
        .system_clk(clk_100mhz), .system_reset(reset),
        .cam_pclk(cam_pclk), .camera_reset(camera_reset), .clear(clear_level),
        .cam_vsync(cam_vsync), .cam_href(cam_href),
        .frame_period_system_cycles(camera_frame_period_cycles),
        .frame_pclk_edges(camera_source_frame_pclk_edges),
        .line_pclk_edges(camera_source_line_pclk_edges),
        .active_bytes(camera_source_active_bytes),
        .active_lines(camera_source_active_lines),
        .source_snapshot(camera_timing_source_snapshot)
    );
    m5_status_snapshot #(.WIDTH(128)) u_camera_timing_snapshot (
        .destination_clk(clk_100mhz), .destination_reset(reset),
        .request(camera_timing_snapshot_request),
        .busy(camera_timing_snapshot_busy),
        .snapshot_valid(camera_timing_snapshot_valid),
        .snapshot_data(camera_timing_snapshot),
        .source_clk(cam_pclk), .source_reset(camera_reset),
        .source_data(camera_timing_source_snapshot)
    );

    always_ff @(posedge cam_pclk or posedge reset_btn) begin
        if (reset_btn) begin
            init_done_camera_sync <= '0;
            clear_camera_sync <= '0;
        end else begin
            init_done_camera_sync <= {init_done_camera_sync[0], camera_init_done};
            clear_camera_sync <= {clear_camera_sync[0], clear_level};
        end
    end
    assign capture_reset = camera_reset || !init_done_camera_sync[1];
    dvp_rgb565_capture #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_capture (
        .cam_pclk(cam_pclk), .reset(capture_reset),
        .clear_errors(clear_camera_sync[1]), .cam_vsync(cam_vsync),
        .cam_href(cam_href), .cam_d(cam_d), .byte_swap(1'b0),
        .pixel_valid(camera_pixel_valid), .pixel_x(camera_pixel_x),
        .pixel_y(camera_pixel_y), .pixel_rgb565(camera_pixel_rgb565),
        .frame_start(camera_frame_start), .frame_end(camera_frame_end),
        .line_end(camera_line_end), .byte_seen(camera_byte_seen),
        .capture_error(camera_capture_error), .error_flags(camera_capture_flags),
        .observed_line_bytes(observed_line_bytes),
        .observed_frame_lines(observed_frame_lines)
    );
    camera_stream_cdc #(
        .FIFO_DEPTH(CAMERA_FIFO_DEPTH), .X_W(X_W), .Y_W(Y_W)
    ) u_camera_cdc (
        .reset(reset_btn), .write_clk(cam_pclk),
        .clear_write_errors(clear_camera_sync[1]), .write_valid(camera_pixel_valid),
        .write_x(camera_pixel_x), .write_y(camera_pixel_y),
        .write_rgb565(camera_pixel_rgb565), .write_frame_start(camera_frame_start),
        .write_frame_end(camera_frame_end), .write_line_end(camera_line_end),
        .read_clk(clk_100mhz), .read_valid(camera_fifo_valid),
        .read_x(camera_fifo_x), .read_y(camera_fifo_y),
        .read_rgb565(camera_fifo_rgb565), .read_frame_start(camera_fifo_frame_start),
        .read_frame_end(camera_fifo_frame_end), .read_line_end(camera_fifo_line_end),
        .overflow_sticky(camera_fifo_overflow),
        .dropped_pixels(camera_dropped_pixels),
        .maximum_occupancy(camera_fifo_maximum)
    );
    camera_stream_adapter #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_camera_adapter (
        .clk(clk_100mhz), .reset(reset), .clear_errors(clear_level),
        .fifo_valid(camera_fifo_valid), .fifo_x(camera_fifo_x),
        .fifo_y(camera_fifo_y), .fifo_rgb565(camera_fifo_rgb565),
        .fifo_frame_start(camera_fifo_frame_start),
        .fifo_frame_end(camera_fifo_frame_end), .fifo_line_end(camera_fifo_line_end),
        .in_valid(gray_valid), .in_x(gray_x), .in_y(gray_y), .in_gray(gray_pixel),
        .in_rgb565(aligned_rgb565), .frame_start(gray_frame_start),
        .frame_end(gray_frame_end), .line_end(gray_line_end),
        .coordinate_error(coordinate_error)
    );
    generate
        if (M7_ENABLE) begin : g_m7_pipeline
            m7_accelerated_pipeline #(
                .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
                .X_W(X_W), .Y_W(Y_W)
            ) u_pipeline (
                .system_clk(clk_100mhz), .reset(reset), .clear_metrics(clear_level),
                .metrics_request(core_metrics_request),
                .synthetic_start(core_synthetic_start),
                .synthetic_frames(core_synthetic_frames), .in_valid(gray_valid),
                .in_x(gray_x), .in_y(gray_y), .in_gray(gray_pixel),
                .out_valid(sobel_valid), .out_x(sobel_x), .out_y(sobel_y),
                .out_pixel(sobel_pixel), .core_locked(core_locked),
                .input_overflow_sticky(core_input_overflow),
                .output_overflow_sticky(core_output_overflow),
                .metrics_busy(core_metrics_busy), .metrics_valid(core_metrics_valid),
                .synthetic_busy(core_synthetic_busy),
                .synthetic_completed_frames(core_synthetic_completed_frames),
                .last_latency_cycles(core_latency_cycles),
                .last_frame_interval_cycles(core_frame_interval_cycles),
                .last_accepted_pixels(core_accepted_pixels),
                .last_produced_pixels(core_produced_pixels),
                .last_valid_gap_cycles(core_valid_gap_cycles),
                .completed_frames(core_completed_frames),
                .last_output_crc(core_output_crc)
            );
            assign pipeline_inputs = core_accepted_pixels;
            assign pipeline_outputs = core_produced_pixels;
            assign pipeline_frames_started = core_completed_frames;
            assign pipeline_frames_completed = core_completed_frames;
            assign pipeline_errors = {30'd0, core_output_overflow, core_input_overflow};
            assign pipeline_crc = 0;
        end else begin : g_m5_pipeline
            conv_pipeline_top #(
                .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
                .X_W(X_W), .Y_W(Y_W)
            ) u_pipeline (
                .clk(clk_100mhz), .reset(reset), .in_valid(gray_valid),
                .in_x(gray_x), .in_y(gray_y), .in_gray(gray_pixel),
                .out_valid(sobel_valid), .out_x(sobel_x), .out_y(sobel_y),
                .out_pixel(sobel_pixel), .accepted_input_pixels(pipeline_inputs),
                .valid_output_pixels(pipeline_outputs),
                .frames_started(pipeline_frames_started),
                .frames_completed(pipeline_frames_completed),
                .protocol_errors(pipeline_errors), .output_checksum(pipeline_crc)
            );
            assign core_locked = 1'b1;
            assign core_input_overflow = 1'b0;
            assign core_output_overflow = 1'b0;
            assign core_metrics_busy = 1'b0;
            assign core_metrics_valid = 1'b0;
            assign core_latency_cycles = 0;
            assign core_frame_interval_cycles = 0;
            assign core_accepted_pixels = 0;
            assign core_produced_pixels = 0;
            assign core_valid_gap_cycles = 0;
            assign core_completed_frames = 0;
            assign core_output_crc = 0;
            assign core_synthetic_busy = 1'b0;
            assign core_synthetic_completed_frames = 0;
        end
    endgenerate
    m7_threshold_sobel #(.X_W(X_W), .Y_W(Y_W)) u_threshold (
        .clk(clk_100mhz), .reset(reset), .in_valid(sobel_valid),
        .in_x(sobel_x), .in_y(sobel_y), .in_pixel(sobel_pixel),
        .requested_threshold_enable(M7_ENABLE && m7_threshold_enable),
        .requested_threshold(m7_threshold), .out_valid(thresholded_valid),
        .out_x(thresholded_x), .out_y(thresholded_y),
        .out_pixel(thresholded_pixel),
        .active_threshold_enable(active_threshold_enable),
        .active_threshold(active_threshold)
    );
    assign processed_valid = M7_ENABLE ? thresholded_valid : sobel_valid;
    assign processed_x = M7_ENABLE ? thresholded_x : sobel_x;
    assign processed_y = M7_ENABLE ? thresholded_y : sobel_y;
    assign processed_pixel = M7_ENABLE ? thresholded_pixel : sobel_pixel;
    assign camera_id_valid = (camera_product_id == 8'h76) &&
                             ((camera_version_id == 8'h70) ||
                              (camera_version_id == 8'h73));

    // Proven Milestone 4 PHY discovery and MII receive path.
    ethernet_ref_clock u_ethernet_clock (
        .clk_100mhz(clk_100mhz), .reset(reset), .eth_ref_clk(eth_ref_clk),
        .clock_ready(ethernet_clock_ready)
    );
    phy_reset #(
        .CLOCK_HZ(CLOCK_HZ), .RESET_US(PHY_RESET_US), .STARTUP_US(PHY_STARTUP_US)
    ) u_phy_reset (
        .clk(clk_100mhz), .reset(reset), .restart(restart_pulse),
        .ref_clock_ready(ethernet_clock_ready), .eth_rstn(eth_rstn), .ready(phy_ready)
    );
    mdio_master #(.CLOCK_HZ(CLOCK_HZ)) u_mdio (
        .clk(clk_100mhz), .reset(reset), .start(mdio_start),
        .write_enable(mdio_write), .phy_address(mdio_phy),
        .register_address(mdio_register), .write_data(mdio_write_data),
        .read_data(mdio_read_data), .busy(mdio_busy), .done(mdio_done),
        .acknowledge_error(mdio_ack_error), .timeout_error(mdio_timeout),
        .mdc(eth_mdc), .mdio_in(eth_mdio), .mdio_drive_low(mdio_drive_low)
    );
    assign eth_mdio = mdio_drive_low ? 1'b0 : 1'bz;
    assign bringup_start = phy_ready && !phy_ready_delayed;
    phy_bringup #(.CLOCK_HZ(CLOCK_HZ)) u_phy_bringup (
        .clk(clk_100mhz), .reset(reset), .start(bringup_start),
        .loopback_enable(1'b0), .command_start(mdio_start),
        .command_write(mdio_write), .command_phy_address(mdio_phy),
        .command_register_address(mdio_register), .command_write_data(mdio_write_data),
        .command_read_data(mdio_read_data), .command_busy(mdio_busy),
        .command_done(mdio_done), .command_ack_error(mdio_ack_error),
        .command_timeout_error(mdio_timeout), .phy_id1(phy_id1), .phy_id2(phy_id2),
        .bmsr(bmsr), .physts(physts), .identity_valid(identity_valid),
        .link_up(link_up), .speed_100(speed_100), .full_duplex(full_duplex),
        .discovery_done(discovery_done), .error_flags(phy_errors)
    );

    always_ff @(posedge eth_rx_clk or posedge reset_btn) begin
        if (reset_btn) begin
            rx_reset_sync <= 2'b11;
            clear_rx_sync <= '0;
            link_rx_sync  <= '0;
            sw1_rx_sync   <= '0;
        end else begin
            rx_reset_sync <= {rx_reset_sync[0], reset || !phy_ready};
            clear_rx_sync <= {clear_rx_sync[0], clear_level};
            link_rx_sync  <= {link_rx_sync[0], link_up};
            sw1_rx_sync   <= {sw1_rx_sync[0], sw_clean[1]};
        end
    end
    always_ff @(posedge eth_tx_clk or posedge reset_btn) begin
        if (reset_btn) tx_reset_sync <= 2'b11;
        else tx_reset_sync <= {tx_reset_sync[0], reset || !phy_ready};
    end
    assign rx_reset = rx_reset_sync[1];
    assign tx_reset = tx_reset_sync[1];

    mii_rx u_mii_rx (
        .rx_clk(eth_rx_clk), .reset(rx_reset), .eth_rxd(eth_rxd),
        .eth_rx_dv(eth_rx_dv), .eth_rxerr(eth_rxerr), .byte_data(rx_byte),
        .byte_valid(rx_byte_valid), .frame_start(rx_frame_start),
        .frame_end(rx_frame_end), .rx_error(rx_error), .odd_nibble(rx_odd)
    );
    ethernet_frame_rx u_frame_rx (
        .clk(eth_rx_clk), .reset(rx_reset), .clear_errors(clear_rx_sync[1]),
        .byte_data(rx_byte), .byte_valid(rx_byte_valid), .frame_start(rx_frame_start),
        .frame_end(rx_frame_end), .mii_rx_error(rx_error), .odd_nibble(rx_odd),
        .read_address(rx_read_address), .read_data(rx_read_data),
        .frame_done(rx_frame_done), .frame_valid(rx_frame_valid),
        .frame_length(rx_frame_length), .destination_mac(rx_destination_mac),
        .source_mac(rx_source_mac), .ether_type(rx_ether_type),
        .source_ip(rx_source_ip), .destination_ip(rx_destination_ip),
        .arp_opcode(rx_arp_opcode), .udp_source_port(rx_udp_source_port),
        .udp_destination_port(rx_udp_destination_port), .udp_length(rx_udp_length),
        .ip_total_length(rx_ip_total_length), .ip_protocol(rx_ip_protocol),
        .ipv4_checksum_valid(rx_ipv4_checksum_valid), .good_frames(good_frames),
        .bad_fcs_frames(bad_fcs_frames), .runt_frames(runt_frames),
        .oversize_frames(oversize_frames), .rx_error_frames(rx_error_frames),
        .protocol_error_frames(protocol_error_frames),
        .sequence_gap_frames(sequence_gap_frames)
    );

    m7_control_receiver #(
        .FPGA_MAC(FPGA_MAC), .FPGA_IP(FPGA_IP), .CONTROL_PORT(CONTROL_PORT)
    ) u_control_receiver (
        .clk(eth_rx_clk), .reset(rx_reset), .clear_errors(clear_rx_sync[1]),
        .link_up(link_rx_sync[1]), .frame_done(rx_frame_done),
        .frame_valid(rx_frame_valid), .frame_length(rx_frame_length),
        .destination_mac(rx_destination_mac), .source_mac(rx_source_mac),
        .ether_type(rx_ether_type), .source_ip(rx_source_ip),
        .destination_ip(rx_destination_ip), .ip_protocol(rx_ip_protocol),
        .ipv4_checksum_valid(rx_ipv4_checksum_valid),
        .ip_total_length(rx_ip_total_length), .udp_source_port(rx_udp_source_port),
        .udp_destination_port(rx_udp_destination_port), .udp_length(rx_udp_length),
        .read_address(control_read_address), .read_data(rx_read_data),
        .parser_busy(control_parser_busy), .command_valid(control_command_valid),
        .command_version(control_version), .command_opcode(control_opcode),
        .command_stream_id(control_stream_id), .command_status(control_status),
        .command_value(control_frame_count),
        .command_source_mac(control_source_mac), .command_source_ip(control_source_ip),
        .command_source_port(control_source_port), .session_active(session_active),
        .session_stream_id(session_stream_id), .session_frame_count(session_frame_count),
        .session_host_mac(session_host_mac), .session_host_ip(session_host_ip),
        .session_host_port(session_host_port), .session_restart(session_restart),
        .requested_profile(requested_profile_rx),
        .requested_threshold_enable(requested_threshold_enable_rx),
        .requested_threshold(requested_threshold_rx),
        .configuration_toggle(configuration_toggle_rx),
        .requested_benchmark_frames(requested_benchmark_frames_rx),
        .benchmark_toggle(benchmark_toggle_rx),
        .control_errors(control_errors)
    );

    // Synchronize the session gate into the processing domain and lock mode per frame.
    always_ff @(posedge clk_100mhz) begin
        if (reset) begin
            session_active_sync <= '0;
            session_stream_sync <= '0;
            stream_complete_sync <= '0;
            selected_frame_stream <= 1'b0;
            tx_underflow_system_sync <= '0;
            mii_underrun_system_sync <= '0;
            tx_overflow_system_sync <= '0;
            tx_length_system_sync <= '0;
            collision_system_sync <= '0;
            configuration_toggle_sync <= '0;
            requested_profile_sync <= {3{M7_DEFAULT_PROFILE}};
            requested_threshold_enable_sync <= '0;
            requested_threshold_sync <= {3{8'd128}};
            configuration_toggle_seen <= 1'b0;
            m7_profile_select <= M7_DEFAULT_PROFILE;
            m7_threshold_enable <= 1'b0;
            m7_threshold <= 8'd128;
            camera_reconfigure_pulse <= 1'b0;
            metrics_refresh_counter <= '0;
            core_metrics_request <= 1'b0;
            benchmark_toggle_sync <= '0;
            requested_benchmark_frames_sync <= {3{16'd1}};
            benchmark_toggle_seen <= 1'b0;
            core_synthetic_start <= 1'b0;
            core_synthetic_frames <= 16'd1;
        end else begin
            session_active_sync <= {session_active_sync[0], session_active};
            session_stream_sync <= {session_stream_sync[0], session_stream_id};
            stream_complete_sync <= {stream_complete_sync[0], camera_stream_complete};
            if (gray_frame_start)
                selected_frame_stream <= sw_clean[1] || session_stream_sync[1];
            tx_underflow_system_sync <= {tx_underflow_system_sync[0], tx_fifo_underflow};
            mii_underrun_system_sync <= {mii_underrun_system_sync[0], mii_underrun};
            tx_overflow_system_sync <= {tx_overflow_system_sync[0], tx_fifo_overflow};
            tx_length_system_sync <= {tx_length_system_sync[0], frame_tx_length_error};
            collision_system_sync <= {collision_system_sync[0], eth_col};
            configuration_toggle_sync <= {
                configuration_toggle_sync[1:0], configuration_toggle_rx
            };
            requested_profile_sync <= {
                requested_profile_sync[3:0], requested_profile_rx
            };
            requested_threshold_enable_sync <= {
                requested_threshold_enable_sync[1:0], requested_threshold_enable_rx
            };
            requested_threshold_sync <= {
                requested_threshold_sync[15:0], requested_threshold_rx
            };
            benchmark_toggle_sync <= {benchmark_toggle_sync[1:0], benchmark_toggle_rx};
            requested_benchmark_frames_sync <= {
                requested_benchmark_frames_sync[31:0], requested_benchmark_frames_rx
            };
            camera_reconfigure_pulse <= 1'b0;
            core_synthetic_start <= 1'b0;
            if (M7_ENABLE && configuration_toggle_sync[2] != configuration_toggle_seen) begin
                configuration_toggle_seen <= configuration_toggle_sync[2];
                m7_profile_select <= requested_profile_sync[5:4];
                m7_threshold_enable <= requested_threshold_enable_sync[2];
                m7_threshold <= requested_threshold_sync[23:16];
                camera_reconfigure_pulse <= 1'b1;
            end
            if (M7_ENABLE && benchmark_toggle_sync[2] != benchmark_toggle_seen) begin
                benchmark_toggle_seen <= benchmark_toggle_sync[2];
                core_synthetic_frames <= requested_benchmark_frames_sync[47:32];
                core_synthetic_start <= 1'b1;
            end
            core_metrics_request <= 1'b0;
            metrics_refresh_counter <= metrics_refresh_counter + 1'b1;
            if (M7_ENABLE && (&metrics_refresh_counter) && !core_metrics_busy)
                core_metrics_request <= 1'b1;
        end
    end
    assign {camera_frame_pclk_edges, camera_active_bytes,
            camera_active_lines, camera_line_pclk_edges} =
        camera_timing_snapshot[127:32];
    assign camera_timing_snapshot_request =
        M7_ENABLE && (&metrics_refresh_counter) && !camera_timing_snapshot_busy;

    assign selected_stream_now = gray_frame_start ?
                                 (sw_clean[1] || session_stream_sync[1]) :
                                 selected_frame_stream;
    assign capture_stream_enable = sw_clean[2] && session_active_sync[1] &&
                                   !stream_complete_sync[1];
    assign stream_write_valid = capture_stream_enable &&
                                (selected_stream_now ? gray_valid : processed_valid);
    assign stream_write_start = selected_stream_now ? gray_frame_start :
                                (processed_valid && processed_x==1 && processed_y==1);
    assign stream_write_end = selected_stream_now ? gray_frame_end :
                              (processed_valid && processed_x==IMAGE_WIDTH-2 &&
                               processed_y==IMAGE_HEIGHT-2);
    assign stream_write_pixel = selected_stream_now ? gray_pixel : processed_pixel;

    m5_stream_fifo #(.FIFO_DEPTH(STREAM_FIFO_DEPTH)) u_stream_fifo (
        .reset(reset_btn), .write_clk(clk_100mhz), .clear_errors(clear_level),
        .stream_enable(capture_stream_enable), .write_valid(stream_write_valid),
        .write_frame_start(stream_write_start), .write_frame_end(stream_write_end),
        .write_stream_id(selected_stream_now), .write_pixel(stream_write_pixel),
        .read_clk(eth_rx_clk), .read_enable(stream_fifo_read),
        .read_valid(stream_fifo_valid), .read_frame_start(stream_fifo_start),
        .read_frame_end(stream_fifo_end),
        .read_discontinuity(stream_fifo_discontinuity),
        .read_stream_id(stream_fifo_id), .read_pixel(stream_fifo_pixel),
        .overflow_sticky(stream_fifo_overflow), .dropped_frames(stream_dropped_frames),
        .dropped_pixels(stream_dropped_pixels), .maximum_occupancy(stream_fifo_maximum)
    );
    m5_stream_packetizer #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .FPGA_MAC(FPGA_MAC), .FPGA_IP(FPGA_IP), .CONTROL_PORT(CONTROL_PORT)
    ) u_packetizer (
        .clk(eth_rx_clk), .reset(rx_reset), .clear_errors(clear_rx_sync[1]),
        .session_active(session_active), .session_restart(session_restart),
        .session_stream_id(sw1_rx_sync[1] || session_stream_id),
        .requested_frame_count(session_frame_count), .host_mac(session_host_mac),
        .host_ip(session_host_ip), .host_port(session_host_port),
        .fifo_valid(stream_fifo_valid), .fifo_frame_start(stream_fifo_start),
        .fifo_frame_end(stream_fifo_end),
        .fifo_discontinuity(stream_fifo_discontinuity),
        .fifo_stream_id(stream_fifo_id), .fifo_pixel(stream_fifo_pixel),
        .fifo_read_enable(stream_fifo_read), .packet_ready(camera_packet_ready),
        .packet_done(frame_tx_done && active_source==SOURCE_CAMERA),
        .frame_index(frame_tx_index), .frame_length(camera_length),
        .frame_data(camera_data), .stream_complete(camera_stream_complete),
        .frames_sent(camera_frames_sent), .packets_sent(camera_packets_sent),
        .bytes_sent(camera_bytes_sent), .packet_errors(camera_packet_errors)
    );

    // Retain one pending descriptor for each higher-priority response type.
    always_ff @(posedge eth_rx_clk or posedge rx_reset) begin
        if (rx_reset) begin
            arp_pending      <= 1'b0;
            echo_pending     <= 1'b0;
            control_pending  <= 1'b0;
            arp_source_mac   <= '0; arp_source_ip <= '0;
            echo_source_mac  <= '0; echo_source_ip <= '0;
            echo_source_port <= '0; echo_udp_length <= '0;
            ack_source_mac   <= '0; ack_source_ip <= '0; ack_source_port <= '0;
            ack_version      <= 8'd1; ack_opcode <= '0; ack_stream_id <= 1'b0;
            ack_status       <= '0; ack_frame_count <= '0;
        end else begin
            if (arp_grant) arp_pending <= 1'b0;
            if (echo_grant) echo_pending <= 1'b0;
            if (control_grant) control_pending <= 1'b0;

            if (rx_frame_done && rx_frame_valid && rx_ether_type==16'h0806 &&
                rx_arp_opcode==16'h0001 && rx_destination_ip==FPGA_IP) begin
                arp_pending    <= 1'b1;
                arp_source_mac <= rx_source_mac;
                arp_source_ip  <= rx_source_ip;
            end
            if (rx_frame_done && rx_frame_valid && rx_ether_type==16'h0800 &&
                rx_ip_protocol==8'h11 && rx_ipv4_checksum_valid &&
                rx_destination_ip==FPGA_IP && rx_udp_destination_port==ECHO_PORT &&
                rx_udp_length>=8 && rx_udp_length<=1480 &&
                rx_ip_total_length==(16'd20+rx_udp_length) &&
                rx_frame_length>=(11'd34+rx_udp_length)) begin
                echo_pending     <= 1'b1;
                echo_source_mac  <= rx_source_mac;
                echo_source_ip   <= rx_source_ip;
                echo_source_port <= rx_udp_source_port;
                echo_udp_length  <= rx_udp_length;
            end
            if (control_command_valid) begin
                control_pending <= 1'b1;
                ack_source_mac  <= control_source_mac;
                ack_source_ip   <= control_source_ip;
                ack_source_port <= control_source_port;
                ack_version     <= control_version;
                ack_opcode      <= control_opcode;
                ack_stream_id   <= control_stream_id;
                ack_status      <= control_status;
                ack_frame_count <= control_frame_count;
                if (control_version == 2 && control_opcode == 3) begin
                    case (control_frame_count[7:0])
                        0: ack_frame_count <= 32'h4d37_0001;
                        1: ack_frame_count <= {
                            link_up, camera_init_done, core_locked,
                            camera_timing_readback_valid, active_threshold_enable,
                            camera_selected_profile, camera_timing_snapshot_valid,
                            active_threshold, combined_errors
                        };
                        2: ack_frame_count <= camera_frame_period_cycles;
                        3: ack_frame_count <= camera_frame_pclk_edges;
                        4: ack_frame_count <= camera_active_bytes;
                        5: ack_frame_count <= {camera_active_lines, camera_line_pclk_edges};
                        6: ack_frame_count <= {camera_fifo_maximum, stream_fifo_maximum};
                        7: ack_frame_count <= core_latency_cycles;
                        8: ack_frame_count <= core_frame_interval_cycles;
                        9: ack_frame_count <= core_accepted_pixels;
                        10: ack_frame_count <= core_produced_pixels;
                        11: ack_frame_count <= core_valid_gap_cycles;
                        12: ack_frame_count <= core_completed_frames;
                        13: ack_frame_count <= camera_timing_readback[39:8];
                        14: ack_frame_count <= {24'd0, camera_timing_readback[7:0]};
                        15: ack_frame_count <= {16'd0, combined_errors};
                        16: ack_frame_count <= {
                            core_synthetic_busy, 15'd0, core_synthetic_completed_frames
                        };
                        17: ack_frame_count <= core_output_crc;
                        default: begin
                            ack_status <= 8'd3;
                            ack_frame_count <= 0;
                        end
                    endcase
                end
            end
        end
    end

    arp_responder #(.FPGA_MAC(FPGA_MAC), .FPGA_IP(FPGA_IP)) u_arp_reply (
        .request_source_mac(arp_source_mac), .request_source_ip(arp_source_ip),
        .reply_index(frame_tx_index), .reply_length(arp_length), .reply_data(arp_data)
    );
    udp_echo #(.FPGA_MAC(FPGA_MAC), .FPGA_IP(FPGA_IP), .UDP_PORT(ECHO_PORT)) u_echo (
        .request_source_mac(echo_source_mac), .request_source_ip(echo_source_ip),
        .request_source_port(echo_source_port), .request_udp_length(echo_udp_length),
        .reply_index(frame_tx_index), .request_read_address(echo_read_address),
        .request_read_data(rx_read_data), .reply_length(echo_length),
        .reply_data(echo_data)
    );
    m7_control_ack #(
        .FPGA_MAC(FPGA_MAC), .FPGA_IP(FPGA_IP), .CONTROL_PORT(CONTROL_PORT)
    ) u_control_ack (
        .destination_mac(ack_source_mac), .destination_ip(ack_source_ip),
        .destination_port(ack_source_port), .command_version(ack_version),
        .command_opcode(ack_opcode), .command_stream_id(ack_stream_id),
        .reply_status(ack_status), .reply_value(ack_frame_count),
        .frame_index(frame_tx_index), .frame_length(control_ack_length),
        .frame_data(control_ack_data)
    );
    assign rx_read_address = (active_source==SOURCE_ECHO) ?
                             echo_read_address : control_read_address;

    m5_tx_scheduler u_scheduler (
        .clk(eth_rx_clk), .reset(rx_reset), .frame_busy(frame_tx_busy),
        .frame_done(frame_tx_done), .arp_pending(arp_pending),
        .control_pending(control_pending), .echo_pending(echo_pending),
        .camera_pending(camera_packet_ready), .test_pending(1'b0),
        .frame_start(frame_tx_start), .active_source(active_source),
        .arp_grant(arp_grant), .control_grant(control_grant),
        .echo_grant(echo_grant), .camera_grant(camera_grant),
        .test_grant(test_grant)
    );
    always_comb begin
        frame_tx_length = camera_length;
        frame_tx_data   = camera_data;
        case (active_source)
            SOURCE_ARP: begin frame_tx_length=arp_length; frame_tx_data=arp_data; end
            SOURCE_CONTROL: begin
                frame_tx_length=control_ack_length; frame_tx_data=control_ack_data;
            end
            SOURCE_ECHO: begin frame_tx_length=echo_length; frame_tx_data=echo_data; end
            default: ;
        endcase
    end
    ethernet_frame_tx u_frame_tx (
        .clk(eth_rx_clk), .reset(rx_reset), .start(frame_tx_start),
        .frame_length(frame_tx_length), .frame_data_index(frame_tx_index),
        .frame_data(frame_tx_data), .output_data(encoded_data),
        .output_valid(encoded_valid), .output_last(encoded_last),
        .output_ready(!tx_fifo_full), .busy(frame_tx_busy), .done(frame_tx_done),
        .length_error(frame_tx_length_error)
    );
    ethernet_async_fifo u_tx_fifo (
        .write_reset(rx_reset), .write_clk(eth_rx_clk),
        .write_enable(encoded_valid && !tx_fifo_full),
        .write_data({encoded_last,encoded_data}), .full(tx_fifo_full),
        .overflow(tx_fifo_overflow), .read_clk(eth_tx_clk), .read_reset(tx_reset),
        .read_enable(tx_fifo_read), .read_data(tx_fifo_output),
        .empty(tx_fifo_empty), .underflow(tx_fifo_underflow)
    );
    assign tx_fifo_read = !tx_fifo_empty && mii_byte_ready;
    mii_tx u_mii_tx (
        .tx_clk(eth_tx_clk), .reset(tx_reset), .byte_data(tx_fifo_output[7:0]),
        .byte_valid(!tx_fifo_empty), .byte_last(tx_fifo_output[8]),
        .byte_ready(mii_byte_ready), .eth_txd(eth_txd), .eth_tx_en(eth_tx_en),
        .underrun(mii_underrun)
    );

    // Request and print a coherent RX-domain status sample with BTN3.
    assign live_bad_frames = bad_fcs_frames + runt_frames + oversize_frames +
                             rx_error_frames + protocol_error_frames;
    assign rx_status_source = {
        live_bad_frames, control_errors, camera_packet_errors,
        camera_bytes_sent, camera_packets_sent, camera_frames_sent,
        camera_packet_errors + control_errors + sequence_gap_frames
    };
    m5_status_snapshot #(.WIDTH(RX_STATUS_W)) u_status_snapshot (
        .destination_clk(clk_100mhz), .destination_reset(reset),
        .request(status_pulse), .busy(snapshot_busy),
        .snapshot_valid(snapshot_valid), .snapshot_data(rx_status_snapshot),
        .source_clk(eth_rx_clk), .source_reset(rx_reset), .source_data(rx_status_source)
    );
    assign {report_bad_frames, report_control_errors, report_packet_errors,
            report_bytes, report_packets, report_frames, report_drops} = rx_status_snapshot;

    always_comb begin
        combined_errors = '0;
        combined_errors[0] = camera_init_error || command_ack_error || command_timeout_error;
        combined_errors[1] = camera_init_done && !camera_id_valid;
        combined_errors[2] = camera_capture_error || coordinate_error;
        combined_errors[3] = camera_fifo_overflow;
        combined_errors[7:4] = phy_errors;
        combined_errors[8] = stream_fifo_overflow;
        combined_errors[9] = (report_packet_errors != 0) || (report_control_errors != 0);
        combined_errors[10] = (report_bad_frames != 0);
        combined_errors[11] = tx_length_system_sync[1] || tx_overflow_system_sync[1];
        combined_errors[12] = tx_underflow_system_sync[1] || mii_underrun_system_sync[1];
        combined_errors[13] = (pipeline_errors != 0);
        combined_errors[14] = collision_system_sync[1];
        combined_errors[15] = M7_ENABLE && !core_locked;
    end
    uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(UART_BAUD)) u_uart (
        .clk(clk_100mhz), .reset(reset), .data(uart_data), .send(uart_send),
        .tx(uart_tx), .busy(uart_busy)
    );
    m5_uart_reporter u_reporter (
        .clk(clk_100mhz), .reset(reset), .start(report_start),
        .camera_pass(camera_init_done && camera_id_valid && !camera_init_error),
        .network_pass(identity_valid && discovery_done && link_up && !(|phy_errors)),
        .stream_pass(!(combined_errors[15:8]) && report_drops==0),
        .camera_id({camera_product_id,camera_version_id}), .link_up(link_up),
        .speed_100(speed_100), .stream_id(selected_frame_stream),
        .frame_count(report_frames), .packet_count(report_packets),
        .byte_count(report_bytes),
        .drop_count(report_drops + stream_dropped_frames),
        .error_flags(combined_errors), .uart_data(uart_data),
        .uart_send(uart_send), .uart_busy(uart_busy), .busy(reporter_busy)
    );

    always_ff @(posedge clk_100mhz) begin
        if (reset) begin
            heartbeat <= '0;
            btn_delayed <= '0;
            camera_clock_ready_delayed <= 1'b0;
            phy_ready_delayed <= 1'b0;
            report_pending <= 1'b0;
            report_start <= 1'b0;
        end else begin
            heartbeat <= heartbeat + 1'b1;
            btn_delayed <= btn_clean;
            camera_clock_ready_delayed <= camera_clock_ready;
            phy_ready_delayed <= phy_ready;
            report_start <= 1'b0;
            if (snapshot_valid)
                report_pending <= 1'b1;
            else if (report_pending && !reporter_busy) begin
                report_pending <= 1'b0;
                report_start <= 1'b1;
            end
        end
    end
    assign led = reset ? 4'b0 : {
        |combined_errors,
        camera_packet_ready || frame_tx_busy,
        camera_init_done && camera_id_valid && identity_valid && link_up,
        heartbeat[26]
    };

    logic unused_debug;
    assign unused_debug = uart_rx ^ eth_crs ^ full_duplex ^ bmsr[0] ^ physts[15] ^
                          camera_byte_seen ^ camera_capture_flags[0] ^ observed_line_bytes[0] ^
                          observed_frame_lines[0] ^ camera_dropped_pixels[0] ^
                          camera_fifo_maximum[0] ^ aligned_rgb565[0] ^ gray_line_end ^
                          pipeline_inputs[0] ^ pipeline_outputs[0] ^
                          pipeline_frames_started[0] ^ pipeline_frames_completed[0] ^
                          pipeline_crc[0] ^ stream_dropped_pixels[0] ^
                          stream_fifo_maximum[0] ^ camera_grant ^ test_grant ^ snapshot_busy ^
                          core_metrics_valid ^ active_threshold[0] ^ camera_timing_readback[0] ^
                          camera_timing_snapshot_valid ^ camera_source_active_lines[0];
endmodule
