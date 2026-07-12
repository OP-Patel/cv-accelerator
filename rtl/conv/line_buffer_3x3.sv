// Returns the current pixel and the pixels at the same column in the prior two rows.
module line_buffer_3x3 #(
    parameter integer IMAGE_WIDTH = 320,
    parameter integer X_W = (IMAGE_WIDTH <= 2) ? 1 : $clog2(IMAGE_WIDTH),
    parameter integer Y_W = 8
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           in_valid,
    input  logic [X_W-1:0] in_x,
    input  logic [Y_W-1:0] in_y,
    input  logic [7:0]     in_pixel,
    output logic           out_valid,
    output logic [X_W-1:0] out_x,
    output logic [Y_W-1:0] out_y,
    output logic [7:0]     row_current,
    output logic [7:0]     row_previous,
    output logic [7:0]     row_two_back
);
    // Even and odd rows alternate banks. Memory contents are deliberately not reset.
    (* ram_style = "block" *) logic [7:0] even_row [0:IMAGE_WIDTH-1];
    (* ram_style = "block" *) logic [7:0] odd_row  [0:IMAGE_WIDTH-1];
    logic [7:0] even_read_data;
    logic [7:0] odd_read_data;
    logic stage_valid;
    logic [X_W-1:0] stage_x;
    logic [Y_W-1:0] stage_y;
    logic [7:0] stage_pixel;

    // This standard synchronous read/write shape maps each row bank to one BRAM.
    always_ff @(posedge clk) begin
        if (reset) begin
            even_read_data <= '0;
        end else if (in_valid) begin
            even_read_data <= even_row[in_x];
            if (!in_y[0]) begin
                even_row[in_x] <= in_pixel;
            end
        end
    end

    // This is the matching odd-row BRAM port.
    always_ff @(posedge clk) begin
        if (reset) begin
            odd_read_data <= '0;
        end else if (in_valid) begin
            odd_read_data <= odd_row[in_x];
            if (in_y[0]) begin
                odd_row[in_x] <= in_pixel;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            stage_valid <= 1'b0;
            stage_x     <= '0;
            stage_y     <= '0;
            stage_pixel <= '0;
            out_valid    <= 1'b0;
            out_x        <= '0;
            out_y        <= '0;
            row_current  <= '0;
            row_previous <= '0;
            row_two_back <= '0;
        end else begin
            stage_valid <= in_valid;
            out_valid   <= stage_valid;

            if (in_valid) begin
                stage_x     <= in_x;
                stage_y     <= in_y;
                stage_pixel <= in_pixel;
            end

            if (stage_valid) begin
                out_x       <= stage_x;
                out_y       <= stage_y;
                row_current <= stage_pixel;

                // Before the current write, its parity bank still contains y-2.
                if (stage_y[0]) begin
                    row_previous <= even_read_data;
                    row_two_back <= odd_read_data;
                end else begin
                    row_previous <= odd_read_data;
                    row_two_back <= even_read_data;
                end
            end
        end
    end
endmodule
