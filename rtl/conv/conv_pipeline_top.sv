// Connects line storage, window generation, Sobel arithmetic, counters, and CRC.
module conv_pipeline_top #(
    parameter integer IMAGE_WIDTH  = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer X_W = (IMAGE_WIDTH <= 2) ? 1 : $clog2(IMAGE_WIDTH),
    parameter integer Y_W = (IMAGE_HEIGHT <= 2) ? 1 : $clog2(IMAGE_HEIGHT)
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           in_valid,
    input  logic [X_W-1:0] in_x,
    input  logic [Y_W-1:0] in_y,
    input  logic [7:0]     in_gray,
    output logic           out_valid,
    output logic [X_W-1:0] out_x,
    output logic [Y_W-1:0] out_y,
    output logic [7:0]     out_pixel,
    output logic [31:0]    accepted_input_pixels,
    output logic [31:0]    valid_output_pixels,
    output logic [31:0]    frames_started,
    output logic [31:0]    frames_completed,
    output logic [31:0]    protocol_errors,
    output logic [31:0]    output_checksum
);
    logic line_valid;
    logic [X_W-1:0] line_x;
    logic [Y_W-1:0] line_y;
    logic [7:0] row_current, row_previous, row_two_back;

    logic window_valid;
    logic [X_W-1:0] window_x;
    logic [Y_W-1:0] window_y;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;

    logic [X_W-1:0] expected_x;
    logic [Y_W-1:0] expected_y;
    logic checksum_clear;

    line_buffer_3x3 #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .X_W(X_W),
        .Y_W(Y_W)
    ) u_line_buffer (
        .clk(clk), .reset(reset),
        .in_valid(in_valid), .in_x(in_x), .in_y(in_y), .in_pixel(in_gray),
        .out_valid(line_valid), .out_x(line_x), .out_y(line_y),
        .row_current(row_current), .row_previous(row_previous), .row_two_back(row_two_back)
    );

    window_3x3 #(.X_W(X_W), .Y_W(Y_W)) u_window (
        .clk(clk), .reset(reset),
        .in_valid(line_valid), .in_x(line_x), .in_y(line_y),
        .row_current(row_current), .row_previous(row_previous), .row_two_back(row_two_back),
        .window_valid(window_valid), .window_x(window_x), .window_y(window_y),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22)
    );

    sobel3x3 #(.X_W(X_W), .Y_W(Y_W)) u_sobel (
        .clk(clk), .reset(reset),
        .in_valid(window_valid), .in_x(window_x), .in_y(window_y),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .out_valid(out_valid), .out_x(out_x), .out_y(out_y), .out_pixel(out_pixel)
    );

    stream_checksum u_checksum (
        .clk(clk), .reset(reset), .clear(checksum_clear),
        .in_valid(out_valid), .in_byte(out_pixel), .checksum(output_checksum)
    );

    // The first cropped output marks the exact output-domain start of a frame.
    assign checksum_clear = out_valid && (out_x == 1) && (out_y == 1);

    always_ff @(posedge clk) begin
        if (reset) begin
            accepted_input_pixels <= 32'd0;
            valid_output_pixels   <= 32'd0;
            frames_started        <= 32'd0;
            frames_completed      <= 32'd0;
            protocol_errors       <= 32'd0;
            expected_x            <= '0;
            expected_y            <= '0;
        end else begin
            if (in_valid) begin
                accepted_input_pixels <= accepted_input_pixels + 1'b1;

                if ((in_x == 0) && (in_y == 0)) begin
                    frames_started <= frames_started + 1'b1;
                    expected_x <= (IMAGE_WIDTH == 1) ? '0 : 1;
                    expected_y <= '0;
                end else begin
                    if ((in_x != expected_x) || (in_y != expected_y)) begin
                        protocol_errors <= protocol_errors + 1'b1;
                    end

                    if (in_x == IMAGE_WIDTH - 1) begin
                        expected_x <= '0;
                        expected_y <= in_y + 1'b1;
                    end else begin
                        expected_x <= in_x + 1'b1;
                        expected_y <= in_y;
                    end
                end

                if ((in_x == IMAGE_WIDTH - 1) && (in_y == IMAGE_HEIGHT - 1)) begin
                    frames_completed <= frames_completed + 1'b1;
                end
            end

            if (out_valid) begin
                if ((out_x == 1) && (out_y == 1)) begin
                    valid_output_pixels <= 32'd1;
                end else begin
                    valid_output_pixels <= valid_output_pixels + 1'b1;
                end
            end
        end
    end
endmodule
