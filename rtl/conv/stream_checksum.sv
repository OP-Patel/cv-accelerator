// Accumulates a standard reflected CRC-32 over valid output bytes.
module stream_checksum (
    input  logic        clk,
    input  logic        reset,
    input  logic        clear,
    input  logic        in_valid,
    input  logic [7:0]  in_byte,
    output logic [31:0] checksum
);
    logic [31:0] crc_state;

    // Advances CRC-32 by one byte using polynomial 0xEDB88320.
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
            crc_state <= 32'hffffffff;
        end else if (clear && in_valid) begin
            crc_state <= next_crc32(32'hffffffff, in_byte);
        end else if (clear) begin
            crc_state <= 32'hffffffff;
        end else if (in_valid) begin
            crc_state <= next_crc32(crc_state, in_byte);
        end
    end

    assign checksum = ~crc_state;
endmodule
