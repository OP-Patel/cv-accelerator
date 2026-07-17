// Converts each byte to the MII-required low nibble then high nibble.
module mii_tx (
    input  logic       tx_clk,
    input  logic       reset,
    input  logic [7:0] byte_data,
    input  logic       byte_valid,
    input  logic       byte_last,
    output logic       byte_ready,
    output logic [3:0] eth_txd,
    output logic       eth_tx_en,
    output logic       underrun
);
    logic high_nibble;
    logic [7:0] saved_byte;
    logic saved_last;

    assign byte_ready = !high_nibble;

    // DP83848 samples TXD/TX_EN on TX_CLK falling edges, so drive on rising edges.
    always_ff @(posedge tx_clk) begin
        if (reset) begin
            high_nibble <= 1'b0;
            saved_byte <= '0;
            saved_last <= 1'b0;
            eth_txd <= '0;
            eth_tx_en <= 1'b0;
            underrun <= 1'b0;
        end else if (!high_nibble) begin
            if (byte_valid) begin
                saved_byte <= byte_data;
                saved_last <= byte_last;
                eth_txd <= byte_data[3:0];
                eth_tx_en <= 1'b1;
                high_nibble <= 1'b1;
            end else begin
                if (eth_tx_en) underrun <= 1'b1;
                eth_txd <= '0;
                eth_tx_en <= 1'b0;
            end
        end else begin
            eth_txd <= saved_byte[7:4];
            high_nibble <= 1'b0;
            if (saved_last) eth_tx_en <= 1'b0;
        end
    end
endmodule
