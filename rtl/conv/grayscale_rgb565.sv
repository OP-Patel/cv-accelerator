// Converts one RGB565 pixel to rounded 8-bit luminance in one pipeline stage.
module grayscale_rgb565 (
    input  logic        clk,
    input  logic        reset,
    input  logic        in_valid,
    input  logic [15:0] in_rgb565,
    output logic        out_valid,
    output logic [7:0]  out_gray
);
    logic [7:0] red_8;
    logic [7:0] green_8;
    logic [7:0] blue_8;
    logic [15:0] weighted_sum;

    always_comb begin
        // Replicating the most-significant bits fills the unused low bits.
        red_8   = {in_rgb565[15:11], in_rgb565[15:13]};
        green_8 = {in_rgb565[10:5],  in_rgb565[10:9]};
        blue_8  = {in_rgb565[4:0],   in_rgb565[4:2]};
        weighted_sum = (red_8 * 8'd77) +
                       (green_8 * 8'd150) +
                       (blue_8 * 8'd29) + 16'd128;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            out_valid <= 1'b0;
            out_gray  <= 8'd0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                out_gray <= weighted_sum[15:8];
            end
        end
    end
endmodule
