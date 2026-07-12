// Computes saturated |Gx| + |Gy| for one 3x3 window using a four-stage pipeline.
module sobel3x3 #(
    parameter integer X_W = 9,
    parameter integer Y_W = 8
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           in_valid,
    input  logic [X_W-1:0] in_x,
    input  logic [Y_W-1:0] in_y,
    input  logic [7:0] p00, p01, p02,
    input  logic [7:0] p10, p11, p12,
    input  logic [7:0] p20, p21, p22,
    output logic           out_valid,
    output logic [X_W-1:0] out_x,
    output logic [Y_W-1:0] out_y,
    output logic [7:0]     out_pixel
);
    logic [10:0] gx_positive_a, gx_negative_a;
    logic [10:0] gy_positive_a, gy_negative_a;
    logic signed [11:0] gx_b, gy_b;
    logic [10:0] magnitude_c;
    logic valid_a, valid_b, valid_c;
    logic [X_W-1:0] x_a, x_b, x_c;
    logic [Y_W-1:0] y_a, y_b, y_c;
    logic [7:0] saturated_c;

    saturate_u8 #(.INPUT_WIDTH(11)) u_saturate (
        .in_value(magnitude_c),
        .out_value(saturated_c)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            valid_a <= 1'b0;
            valid_b <= 1'b0;
            valid_c <= 1'b0;
            out_valid <= 1'b0;
            gx_positive_a <= '0;
            gx_negative_a <= '0;
            gy_positive_a <= '0;
            gy_negative_a <= '0;
            gx_b <= '0;
            gy_b <= '0;
            magnitude_c <= '0;
            x_a <= '0; x_b <= '0; x_c <= '0; out_x <= '0;
            y_a <= '0; y_b <= '0; y_c <= '0; out_y <= '0;
            out_pixel <= '0;
        end else begin
            // Stage A groups positive and negative kernel terms without signed casts.
            valid_a <= in_valid;
            x_a <= in_x;
            y_a <= in_y;
            if (in_valid) begin
                gx_positive_a <= {3'd0, p02} + ({3'd0, p12} << 1) + {3'd0, p22};
                gx_negative_a <= {3'd0, p00} + ({3'd0, p10} << 1) + {3'd0, p20};
                gy_positive_a <= {3'd0, p20} + ({3'd0, p21} << 1) + {3'd0, p22};
                gy_negative_a <= {3'd0, p00} + ({3'd0, p01} << 1) + {3'd0, p02};
            end

            // Stage B forms signed gradients. Twelve bits comfortably hold intermediate subtraction.
            valid_b <= valid_a;
            x_b <= x_a;
            y_b <= y_a;
            if (valid_a) begin
                gx_b <= $signed({1'b0, gx_positive_a}) - $signed({1'b0, gx_negative_a});
                gy_b <= $signed({1'b0, gy_positive_a}) - $signed({1'b0, gy_negative_a});
            end

            // Stage C takes absolute values and adds them; the maximum is 2040.
            valid_c <= valid_b;
            x_c <= x_b;
            y_c <= y_b;
            if (valid_b) begin
                magnitude_c <= (gx_b < 0 ? -gx_b : gx_b) +
                               (gy_b < 0 ? -gy_b : gy_b);
            end

            // Stage D clamps the result and keeps coordinates aligned with it.
            out_valid <= valid_c;
            out_x <= x_c;
            out_y <= y_c;
            if (valid_c) begin
                out_pixel <= saturated_c;
            end
        end
    end
endmodule
