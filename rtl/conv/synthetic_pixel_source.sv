// Streams deterministic raster patterns at one pixel per clock after a start pulse.
module synthetic_pixel_source #(
    parameter integer IMAGE_WIDTH  = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer X_W = (IMAGE_WIDTH <= 2) ? 1 : $clog2(IMAGE_WIDTH),
    parameter integer Y_W = (IMAGE_HEIGHT <= 2) ? 1 : $clog2(IMAGE_HEIGHT)
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           start,
    input  logic [2:0]     pattern_select,
    output logic           busy,
    output logic           frame_done,
    output logic           out_valid,
    output logic [X_W-1:0] out_x,
    output logic [Y_W-1:0] out_y,
    output logic [7:0]     out_gray
);
    logic [2:0] active_pattern;
    logic [X_W-1:0] source_x;
    logic [Y_W-1:0] source_y;

    // Generates black, white, vertical edge, horizontal edge, checkerboard, or coordinate hash.
    function automatic logic [7:0] pattern_pixel(
        input logic [2:0] pattern,
        input logic [X_W-1:0] x,
        input logic [Y_W-1:0] y
    );
        case (pattern)
            3'd0: pattern_pixel = 8'd0;
            3'd1: pattern_pixel = 8'd255;
            3'd2: pattern_pixel = (x < IMAGE_WIDTH / 2) ? 8'd0 : 8'd255;
            3'd3: pattern_pixel = (y < IMAGE_HEIGHT / 2) ? 8'd0 : 8'd255;
            3'd4: pattern_pixel = x[3] ^ y[3] ? 8'd255 : 8'd0;
            default: pattern_pixel = (x * 8'd17) + (y * 8'd31) + (x ^ y);
        endcase
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            busy           <= 1'b0;
            frame_done     <= 1'b0;
            out_valid      <= 1'b0;
            out_x          <= '0;
            out_y          <= '0;
            out_gray       <= '0;
            active_pattern <= '0;
            source_x       <= '0;
            source_y       <= '0;
        end else begin
            frame_done <= 1'b0;
            out_valid  <= 1'b0;

            if (!busy) begin
                if (start) begin
                    busy           <= 1'b1;
                    active_pattern <= pattern_select;
                    source_x       <= '0;
                    source_y       <= '0;
                end
            end else begin
                out_valid <= 1'b1;
                out_x     <= source_x;
                out_y     <= source_y;
                out_gray  <= pattern_pixel(active_pattern, source_x, source_y);

                if ((source_x == IMAGE_WIDTH - 1) && (source_y == IMAGE_HEIGHT - 1)) begin
                    busy       <= 1'b0;
                    frame_done <= 1'b1;
                end else if (source_x == IMAGE_WIDTH - 1) begin
                    source_x <= '0;
                    source_y <= source_y + 1'b1;
                end else begin
                    source_x <= source_x + 1'b1;
                end
            end
        end
    end
endmodule
