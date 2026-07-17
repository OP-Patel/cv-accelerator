// Reflected Ethernet/ZIP CRC-32: polynomial 0xEDB88320, init/final XOR all ones.
module ethernet_fcs (
    input  logic        clk,
    input  logic        reset,
    input  logic        clear,
    input  logic        enable,
    input  logic [7:0]  data,
    output logic [31:0] crc_state,
    output logic [31:0] fcs
);
    function automatic logic [31:0] next_crc32(
        input logic [31:0] crc,
        input logic [7:0] byte_value
    );
        logic [31:0] value;
        integer bit_index;
        begin
            value = crc;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value = (value >> 1) ^ ((value[0] ^ byte_value[bit_index]) ? 32'hEDB88320 : 32'h0);
            end
            next_crc32 = value;
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset || clear) crc_state <= 32'hFFFF_FFFF;
        else if (enable) crc_state <= next_crc32(crc_state, data);
    end
    assign fcs = ~crc_state;
endmodule
