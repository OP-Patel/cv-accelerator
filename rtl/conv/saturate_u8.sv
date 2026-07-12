// Clamps an unsigned value to the range of one 8-bit pixel.
module saturate_u8 #(
    parameter integer INPUT_WIDTH = 11
) (
    input  logic [INPUT_WIDTH-1:0] in_value,
    output logic [7:0]             out_value
);
    always_comb begin
        if (|in_value[INPUT_WIDTH-1:8]) begin
            out_value = 8'hff;
        end else begin
            out_value = in_value[7:0];
        end
    end
endmodule
