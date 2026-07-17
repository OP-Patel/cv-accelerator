// Reconstructs bytes from MII low/high nibbles and marks frame boundaries.
module mii_rx (
    input  logic       rx_clk,
    input  logic       reset,
    input  logic [3:0] eth_rxd,
    input  logic       eth_rx_dv,
    input  logic       eth_rxerr,
    output logic [7:0] byte_data,
    output logic       byte_valid,
    output logic       frame_start,
    output logic       frame_end,
    output logic       rx_error,
    output logic       odd_nibble
);
    logic have_low, in_frame;
    logic [3:0] low_nibble;

    // The PHY launches after one RX_CLK rising edge; capture on the next rising edge.
    always_ff @(posedge rx_clk or posedge reset) begin
        if (reset) begin
            have_low <= 1'b0;
            in_frame <= 1'b0;
            low_nibble <= '0;
            byte_data <= '0;
            byte_valid <= 1'b0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
            rx_error <= 1'b0;
            odd_nibble <= 1'b0;
        end else begin
            byte_valid <= 1'b0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
            if (eth_rx_dv) begin
                if (!in_frame) begin
                    in_frame <= 1'b1;
                    frame_start <= 1'b1;
                    rx_error <= 1'b0;
                    odd_nibble <= 1'b0;
                end
                if (!have_low) begin
                    low_nibble <= eth_rxd;
                    have_low <= 1'b1;
                end else begin
                    byte_data <= {eth_rxd, low_nibble};
                    byte_valid <= 1'b1;
                    have_low <= 1'b0;
                end
                if (eth_rxerr) rx_error <= 1'b1;
            end else if (in_frame) begin
                in_frame <= 1'b0;
                frame_end <= 1'b1;
                odd_nibble <= have_low;
                have_low <= 1'b0;
            end
        end
    end
endmodule
