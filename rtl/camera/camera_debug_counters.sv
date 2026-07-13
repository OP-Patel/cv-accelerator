// Counts one completed camera-to-Sobel frame and snapshots stable UART values.
module camera_debug_counters #(
    parameter integer IMAGE_WIDTH  = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer X_W = (IMAGE_WIDTH <= 2) ? 1 : $clog2(IMAGE_WIDTH),
    parameter integer Y_W = (IMAGE_HEIGHT <= 2) ? 1 : $clog2(IMAGE_HEIGHT)
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           pixel_valid,
    input  logic [7:0]     pixel_gray,
    input  logic           pixel_frame_start,
    input  logic           pixel_frame_end,
    input  logic           pixel_line_end,
    input  logic           raw_mode,
    input  logic           sobel_valid,
    input  logic [X_W-1:0] sobel_x,
    input  logic [Y_W-1:0] sobel_y,
    input  logic [7:0]     sobel_pixel,
    input  logic [15:0]    live_error_flags,
    input  logic           freeze_snapshot,
    output logic           snapshot_valid,
    output logic [31:0]    frame_number,
    output logic [15:0]    line_count,
    output logic [31:0]    pixel_count,
    output logic [31:0]    gray_crc,
    output logic [31:0]    sobel_count,
    output logic [31:0]    sobel_crc,
    output logic [15:0]    error_flags
);
    logic [15:0] current_lines;
    logic [31:0] current_pixels, current_sobel_pixels;
    logic [31:0] gray_crc_state, sobel_crc_state;
    logic finalize_pending;

    // Advances the same reflected CRC-32 used by the Milestone 2 checker.
    function automatic logic [31:0] next_crc32(
        input logic [31:0] current_crc,
        input logic [7:0] data
    );
        logic [31:0] crc;
        integer bit_index;
        begin
            crc = current_crc ^ {24'd0, data};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (crc[0]) begin
                    crc = (crc >> 1) ^ 32'hedb88320;
                end else begin
                    crc = crc >> 1;
                end
            end
            next_crc32 = crc;
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            current_lines        <= '0;
            current_pixels       <= '0;
            current_sobel_pixels <= '0;
            gray_crc_state       <= 32'hffffffff;
            sobel_crc_state      <= 32'hffffffff;
            finalize_pending     <= 1'b0;
            snapshot_valid       <= 1'b0;
            frame_number         <= '0;
            line_count           <= '0;
            pixel_count          <= '0;
            gray_crc             <= '0;
            sobel_count          <= '0;
            sobel_crc            <= '0;
            error_flags          <= '0;
        end else begin
            snapshot_valid <= 1'b0;

            if (pixel_valid && pixel_frame_start) begin
                current_lines        <= pixel_line_end ? 16'd1 : 16'd0;
                current_pixels       <= 32'd1;
                current_sobel_pixels <= '0;
                gray_crc_state       <= next_crc32(32'hffffffff, pixel_gray);
                sobel_crc_state      <= 32'hffffffff;
            end else if (pixel_valid) begin
                current_pixels <= current_pixels + 1'b1;
                gray_crc_state <= next_crc32(gray_crc_state, pixel_gray);
                if (pixel_line_end) begin
                    current_lines <= current_lines + 1'b1;
                end
            end

            if (raw_mode && pixel_valid && pixel_frame_end) begin
                finalize_pending <= 1'b1;
            end

            if (!raw_mode && sobel_valid) begin
                current_sobel_pixels <= current_sobel_pixels + 1'b1;
                sobel_crc_state <= next_crc32(sobel_crc_state, sobel_pixel);
                if ((sobel_x == IMAGE_WIDTH - 2) && (sobel_y == IMAGE_HEIGHT - 2)) begin
                    finalize_pending <= 1'b1;
                end
            end

            // Wait one cycle so the final Sobel count and CRC are included.
            if (finalize_pending) begin
                finalize_pending <= 1'b0;
                if (!freeze_snapshot) begin
                    snapshot_valid <= 1'b1;
                    frame_number   <= frame_number + 1'b1;
                    line_count     <= current_lines;
                    pixel_count    <= current_pixels;
                    gray_crc       <= ~gray_crc_state;
                    sobel_count    <= current_sobel_pixels;
                    sobel_crc      <= ~sobel_crc_state;
                    error_flags    <= live_error_flags;
                end
            end
        end
    end
endmodule
