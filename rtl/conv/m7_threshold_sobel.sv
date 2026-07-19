// Applies an optional binary threshold without changing the reference Sobel path.
module m7_threshold_sobel #(
    parameter integer X_W = 9,
    parameter integer Y_W = 8
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           in_valid,
    input  logic [X_W-1:0] in_x,
    input  logic [Y_W-1:0] in_y,
    input  logic [7:0]     in_pixel,
    input  logic           requested_threshold_enable,
    input  logic [7:0]     requested_threshold,
    output logic           out_valid,
    output logic [X_W-1:0] out_x,
    output logic [Y_W-1:0] out_y,
    output logic [7:0]     out_pixel,
    output logic           active_threshold_enable,
    output logic [7:0]     active_threshold
);
    logic frame_threshold_enable;
    logic [7:0] frame_threshold;
    logic selected_enable;
    logic [7:0] selected_threshold;

    // The first cropped pixel is also processed with the newly locked settings.
    always_comb begin
        selected_enable = frame_threshold_enable;
        selected_threshold = frame_threshold;
        if (in_valid && (in_x == 1) && (in_y == 1)) begin
            selected_enable = requested_threshold_enable;
            selected_threshold = requested_threshold;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            frame_threshold_enable <= 1'b0;
            frame_threshold <= 8'd128;
            out_valid <= 1'b0;
            out_x <= '0;
            out_y <= '0;
            out_pixel <= '0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                if ((in_x == 1) && (in_y == 1)) begin
                    frame_threshold_enable <= requested_threshold_enable;
                    frame_threshold <= requested_threshold;
                end
                out_x <= in_x;
                out_y <= in_y;
                out_pixel <= selected_enable ?
                             ((in_pixel >= selected_threshold) ? 8'hff : 8'h00) :
                             in_pixel;
            end
        end
    end

    assign active_threshold_enable = frame_threshold_enable;
    assign active_threshold = frame_threshold;
endmodule
