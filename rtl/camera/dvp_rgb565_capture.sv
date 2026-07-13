// Assembles OV7670 DVP bytes into raster-ordered RGB565 pixels in cam_pclk.
module dvp_rgb565_capture #(
    parameter integer IMAGE_WIDTH  = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer X_W = (IMAGE_WIDTH <= 2) ? 1 : $clog2(IMAGE_WIDTH),
    parameter integer Y_W = (IMAGE_HEIGHT <= 2) ? 1 : $clog2(IMAGE_HEIGHT)
) (
    input  logic           cam_pclk,
    input  logic           reset,
    input  logic           clear_errors,
    input  logic           cam_vsync,
    input  logic           cam_href,
    input  logic [7:0]     cam_d,
    input  logic           byte_swap,
    output logic           pixel_valid,
    output logic [X_W-1:0] pixel_x,
    output logic [Y_W-1:0] pixel_y,
    output logic [15:0]    pixel_rgb565,
    output logic           frame_start,
    output logic           frame_end,
    output logic           line_end,
    output logic           byte_seen,
    output logic           capture_error,
    output logic [3:0]     error_flags
);
    localparam integer X_COUNT_W = $clog2(IMAGE_WIDTH + 2);
    localparam integer Y_COUNT_W = $clog2(IMAGE_HEIGHT + 2);

    logic in_frame;
    logic previous_href;
    logic have_first_byte;
    logic [7:0] first_byte;
    logic [X_COUNT_W-1:0] x_count;
    logic [Y_COUNT_W-1:0] y_count;

    always_ff @(posedge cam_pclk) begin
        if (reset) begin
            in_frame       <= 1'b0;
            previous_href  <= 1'b0;
            have_first_byte <= 1'b0;
            first_byte     <= '0;
            x_count        <= '0;
            y_count        <= '0;
            pixel_valid    <= 1'b0;
            pixel_x        <= '0;
            pixel_y        <= '0;
            pixel_rgb565   <= '0;
            frame_start    <= 1'b0;
            frame_end      <= 1'b0;
            line_end       <= 1'b0;
            byte_seen      <= 1'b0;
            error_flags    <= '0;
        end else begin
            pixel_valid <= 1'b0;
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            line_end    <= 1'b0;
            byte_seen   <= 1'b0;

            if (clear_errors) begin
                error_flags <= '0;
            end

            // VSYNC is configured active high: high is frame blanking.
            if (cam_vsync) begin
                if (in_frame) begin
                    if ((y_count != IMAGE_HEIGHT) || previous_href || have_first_byte) begin
                        error_flags[2] <= 1'b1;
                    end
                end
                in_frame        <= 1'b0;
                previous_href   <= 1'b0;
                have_first_byte <= 1'b0;
                x_count         <= '0;
                y_count         <= '0;
            end else begin
                if (!in_frame) begin
                    in_frame        <= 1'b1;
                    previous_href   <= 1'b0;
                    have_first_byte <= 1'b0;
                    x_count         <= '0;
                    y_count         <= '0;
                end

                if (in_frame && previous_href && !cam_href) begin
                    line_end <= 1'b1;
                    if (have_first_byte) begin
                        error_flags[0] <= 1'b1;
                    end
                    if (x_count != IMAGE_WIDTH) begin
                        error_flags[1] <= 1'b1;
                    end
                    have_first_byte <= 1'b0;
                    x_count <= '0;
                    if (y_count < IMAGE_HEIGHT + 1) begin
                        y_count <= y_count + 1'b1;
                    end
                end

                if (in_frame && cam_href) begin
                    byte_seen <= 1'b1;
                    if (!previous_href) begin
                        x_count         <= '0;
                        have_first_byte <= 1'b0;
                    end

                    if (!have_first_byte) begin
                        first_byte     <= cam_d;
                        have_first_byte <= 1'b1;
                    end else begin
                        have_first_byte <= 1'b0;
                        if ((x_count < IMAGE_WIDTH) && (y_count < IMAGE_HEIGHT)) begin
                            pixel_valid  <= 1'b1;
                            pixel_x      <= x_count[X_W-1:0];
                            pixel_y      <= y_count[Y_W-1:0];
                            pixel_rgb565 <= byte_swap ? {cam_d, first_byte} : {first_byte, cam_d};
                            frame_start  <= (x_count == 0) && (y_count == 0);
                            line_end     <= (x_count == IMAGE_WIDTH - 1);
                            frame_end    <= (x_count == IMAGE_WIDTH - 1) &&
                                            (y_count == IMAGE_HEIGHT - 1);
                        end else begin
                            error_flags[3] <= 1'b1;
                        end
                        if (x_count < IMAGE_WIDTH + 1) begin
                            x_count <= x_count + 1'b1;
                        end
                    end
                end

                previous_href <= cam_href;
            end
        end
    end

    assign capture_error = |error_flags;
endmodule
