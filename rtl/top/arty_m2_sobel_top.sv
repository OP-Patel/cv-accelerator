// Runs deterministic 320x240 Sobel tests on the Arty A7 and reports CRC results by UART.
module arty_m2_sobel_top #(
    parameter integer CLOCK_HZ        = 100_000_000,
    parameter integer UART_BAUD       = 115_200,
    parameter integer DEBOUNCE_CYCLES = 1_000_000,
    parameter integer IMAGE_WIDTH     = 320,
    parameter integer IMAGE_HEIGHT    = 240,
    parameter integer HEARTBEAT_BIT    = 26
) (
    input  logic clk_100mhz,
    input  logic reset_btn,
    input  logic [2:0] btn,
    input  logic [3:0] sw,
    input  logic uart_rx,
    output logic uart_tx,
    output logic [3:0] led
);
    localparam integer X_W = $clog2(IMAGE_WIDTH);
    localparam integer Y_W = $clog2(IMAGE_HEIGHT);
    localparam logic [31:0] EXPECTED_OUTPUT_COUNT = (IMAGE_WIDTH - 2) * (IMAGE_HEIGHT - 2);

    logic reset;
    logic [26:0] heartbeat_counter;
    logic start_clean, start_delayed;
    logic start_pulse;
    logic [2:0] pattern_clean;
    logic [2:0] active_pattern;
    logic source_busy, source_done, source_valid;
    logic [X_W-1:0] source_x;
    logic [Y_W-1:0] source_y;
    logic [7:0] source_gray;
    logic result_valid;
    logic [X_W-1:0] result_x;
    logic [Y_W-1:0] result_y;
    logic [7:0] result_pixel;
    logic [31:0] input_count, output_count;
    logic [31:0] frames_started, frames_completed, protocol_errors;
    logic [31:0] result_crc;
    logic finalize_pending;
    logic result_pass;
    logic pass_sticky, error_sticky;
    logic [7:0] uart_data;
    logic uart_send, uart_busy, reporter_busy;

    (* ASYNC_REG = "TRUE" *) logic [1:0] uart_rx_sync;

    reset_sync u_reset_sync (
        .clk(clk_100mhz), .async_reset_in(reset_btn), .sync_reset_out(reset)
    );

    debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_start_debounce (
        .clk(clk_100mhz), .reset(reset), .noisy_in(btn[0]), .clean_out(start_clean)
    );

    genvar switch_index;
    generate
        for (switch_index = 0; switch_index < 3; switch_index = switch_index + 1) begin : g_pattern_debounce
            debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_switch_debounce (
                .clk(clk_100mhz), .reset(reset), .noisy_in(sw[switch_index]),
                .clean_out(pattern_clean[switch_index])
            );
        end
    endgenerate

    synthetic_pixel_source #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_source (
        .clk(clk_100mhz), .reset(reset),
        .start(start_pulse && !reporter_busy), .pattern_select(pattern_clean),
        .busy(source_busy), .frame_done(source_done),
        .out_valid(source_valid), .out_x(source_x), .out_y(source_y), .out_gray(source_gray)
    );

    conv_pipeline_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .X_W(X_W), .Y_W(Y_W)
    ) u_pipeline (
        .clk(clk_100mhz), .reset(reset),
        .in_valid(source_valid), .in_x(source_x), .in_y(source_y), .in_gray(source_gray),
        .out_valid(result_valid), .out_x(result_x), .out_y(result_y), .out_pixel(result_pixel),
        .accepted_input_pixels(input_count), .valid_output_pixels(output_count),
        .frames_started(frames_started), .frames_completed(frames_completed),
        .protocol_errors(protocol_errors), .output_checksum(result_crc)
    );

    uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD_RATE(UART_BAUD)) u_uart_tx (
        .clk(clk_100mhz), .reset(reset), .data(uart_data), .send(uart_send),
        .tx(uart_tx), .busy(uart_busy)
    );

    m2_uart_reporter u_reporter (
        .clk(clk_100mhz), .reset(reset), .start(finalize_pending),
        .pattern(active_pattern), .input_count(IMAGE_WIDTH * IMAGE_HEIGHT),
        .output_count(output_count), .checksum(result_crc), .pass(result_pass),
        .uart_data(uart_data), .uart_send(uart_send), .uart_busy(uart_busy), .busy(reporter_busy)
    );

    // Returns Python-derived CRC-32 values for the six built-in 320x240 patterns.
    function automatic logic [31:0] expected_crc(input logic [2:0] pattern);
        case (pattern)
            3'd0: expected_crc = 32'hcb78a10b;
            3'd1: expected_crc = 32'hcb78a10b;
            3'd2: expected_crc = 32'h18c9d29e;
            3'd3: expected_crc = 32'h01a15b08;
            3'd4: expected_crc = 32'h0d9da21c;
            default: expected_crc = 32'he09929fa;
        endcase
    endfunction

    assign start_pulse = start_clean && !start_delayed && !source_busy;
    assign result_pass = (IMAGE_WIDTH == 320) && (IMAGE_HEIGHT == 240) &&
                         (output_count == EXPECTED_OUTPUT_COUNT) &&
                         (result_crc == expected_crc(active_pattern)) &&
                         (protocol_errors == 0);

    always_ff @(posedge clk_100mhz) begin
        if (reset) begin
            heartbeat_counter <= '0;
            uart_rx_sync       <= 2'b11;
            start_delayed      <= 1'b0;
            active_pattern     <= '0;
            finalize_pending   <= 1'b0;
            pass_sticky        <= 1'b0;
            error_sticky       <= 1'b0;
        end else begin
            heartbeat_counter <= heartbeat_counter + 1'b1;
            uart_rx_sync <= {uart_rx_sync[0], uart_rx};
            start_delayed <= start_clean;
            finalize_pending <= 1'b0;

            if (start_pulse && !reporter_busy) begin
                active_pattern <= pattern_clean;
                pass_sticky  <= 1'b0;
                error_sticky <= 1'b0;
            end

            if (result_valid &&
                (result_x == IMAGE_WIDTH - 2) &&
                (result_y == IMAGE_HEIGHT - 2)) begin
                finalize_pending <= 1'b1;
            end

            if (finalize_pending) begin
                pass_sticky  <= result_pass;
                error_sticky <= !result_pass;
            end
        end
    end

    assign led = reset ? 4'b0000 : {
        error_sticky,
        pass_sticky,
        source_busy,
        heartbeat_counter[HEARTBEAT_BIT]
    };
endmodule
