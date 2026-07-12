// Builds a 3x3 neighborhood; p00 is top-left and p22 is bottom-right.
module window_3x3 #(
    parameter integer X_W = 9,
    parameter integer Y_W = 8
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           in_valid,
    input  logic [X_W-1:0] in_x,
    input  logic [Y_W-1:0] in_y,
    input  logic [7:0]     row_current,
    input  logic [7:0]     row_previous,
    input  logic [7:0]     row_two_back,
    output logic           window_valid,
    output logic [X_W-1:0] window_x,
    output logic [Y_W-1:0] window_y,
    output logic [7:0] p00, p01, p02,
    output logic [7:0] p10, p11, p12,
    output logic [7:0] p20, p21, p22
);
    logic [7:0] top_delay_1, top_delay_2;
    logic [7:0] middle_delay_1, middle_delay_2;
    logic [7:0] bottom_delay_1, bottom_delay_2;

    always_ff @(posedge clk) begin
        if (reset) begin
            window_valid <= 1'b0;
            window_x <= '0;
            window_y <= '0;
            top_delay_1 <= '0;
            top_delay_2 <= '0;
            middle_delay_1 <= '0;
            middle_delay_2 <= '0;
            bottom_delay_1 <= '0;
            bottom_delay_2 <= '0;
            p00 <= '0; p01 <= '0; p02 <= '0;
            p10 <= '0; p11 <= '0; p12 <= '0;
            p20 <= '0; p21 <= '0; p22 <= '0;
        end else begin
            window_valid <= 1'b0;
            if (in_valid) begin
                // Restart horizontal history at the start of every line.
                if (in_x == 0) begin
                    top_delay_1    <= row_two_back;
                    top_delay_2    <= '0;
                    middle_delay_1 <= row_previous;
                    middle_delay_2 <= '0;
                    bottom_delay_1 <= row_current;
                    bottom_delay_2 <= '0;
                end else begin
                    top_delay_2    <= top_delay_1;
                    top_delay_1    <= row_two_back;
                    middle_delay_2 <= middle_delay_1;
                    middle_delay_1 <= row_previous;
                    bottom_delay_2 <= bottom_delay_1;
                    bottom_delay_1 <= row_current;
                end

                if ((in_x >= 2) && (in_y >= 2)) begin
                    p00 <= top_delay_2;
                    p01 <= top_delay_1;
                    p02 <= row_two_back;
                    p10 <= middle_delay_2;
                    p11 <= middle_delay_1;
                    p12 <= row_previous;
                    p20 <= bottom_delay_2;
                    p21 <= bottom_delay_1;
                    p22 <= row_current;
                    window_x <= in_x - 1'b1;
                    window_y <= in_y - 1'b1;
                    window_valid <= 1'b1;
                end
            end
        end
    end
endmodule
