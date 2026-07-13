// Converts FIFO RGB565 records into the registered Milestone 2 grayscale stream.
module camera_stream_adapter #(
    parameter integer IMAGE_WIDTH  = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer X_W = (IMAGE_WIDTH <= 2) ? 1 : $clog2(IMAGE_WIDTH),
    parameter integer Y_W = (IMAGE_HEIGHT <= 2) ? 1 : $clog2(IMAGE_HEIGHT)
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           clear_errors,
    input  logic           fifo_valid,
    input  logic [X_W-1:0] fifo_x,
    input  logic [Y_W-1:0] fifo_y,
    input  logic [15:0]    fifo_rgb565,
    input  logic           fifo_frame_start,
    input  logic           fifo_frame_end,
    input  logic           fifo_line_end,
    output logic           in_valid,
    output logic [X_W-1:0] in_x,
    output logic [Y_W-1:0] in_y,
    output logic [7:0]     in_gray,
    output logic [15:0]    in_rgb565,
    output logic           frame_start,
    output logic           frame_end,
    output logic           line_end,
    output logic           coordinate_error
);
    logic gray_valid;
    logic [7:0] gray_value;
    logic [X_W-1:0] delayed_x;
    logic [Y_W-1:0] delayed_y;
    logic [15:0] delayed_rgb565;
    logic delayed_frame_start, delayed_frame_end, delayed_line_end;

    grayscale_rgb565 u_grayscale (
        .clk(clk), .reset(reset),
        .in_valid(fifo_valid), .in_rgb565(fifo_rgb565),
        .out_valid(gray_valid), .out_gray(gray_value)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            delayed_x           <= '0;
            delayed_y           <= '0;
            delayed_rgb565      <= '0;
            delayed_frame_start <= 1'b0;
            delayed_frame_end   <= 1'b0;
            delayed_line_end    <= 1'b0;
            coordinate_error    <= 1'b0;
        end else begin
            if (clear_errors) begin
                coordinate_error <= 1'b0;
            end
            if (fifo_valid) begin
                delayed_x           <= fifo_x;
                delayed_y           <= fifo_y;
                delayed_rgb565      <= fifo_rgb565;
                delayed_frame_start <= fifo_frame_start;
                delayed_frame_end   <= fifo_frame_end;
                delayed_line_end    <= fifo_line_end;
                if ((fifo_x >= IMAGE_WIDTH) || (fifo_y >= IMAGE_HEIGHT)) begin
                    coordinate_error <= 1'b1;
                end
            end
        end
    end

    assign in_valid    = gray_valid;
    assign in_x        = delayed_x;
    assign in_y        = delayed_y;
    assign in_gray     = gray_value;
    assign in_rgb565   = delayed_rgb565;
    assign frame_start = gray_valid && delayed_frame_start;
    assign frame_end   = gray_valid && delayed_frame_end;
    assign line_end    = gray_valid && delayed_line_end;
endmodule
