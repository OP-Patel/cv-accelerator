module uart_tx #(
    parameter integer CLOCK_HZ  = 100_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input  logic clk,
    input  logic reset,
    input  logic [7:0] data,
    input  logic send,
    output logic tx,
    output logic busy
);

    localparam integer CLOCKS_PER_BIT =
        (CLOCK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer BAUD_COUNTER_WIDTH =
        (CLOCKS_PER_BIT <= 1) ? 1 : $clog2(CLOCKS_PER_BIT);

    logic [BAUD_COUNTER_WIDTH-1:0] baud_counter;
    logic [3:0] bit_index;
    logic [9:0] frame;

    always_ff @(posedge clk) begin
        if (reset) begin
            tx           <= 1'b1;
            busy         <= 1'b0;
            baud_counter <= '0;
            bit_index    <= '0;
            frame        <= 10'h3ff;
        end else if (!busy) begin
            tx           <= 1'b1;
            baud_counter <= '0;
            bit_index    <= '0;

            if (send) begin
                frame <= {1'b1, data, 1'b0};
                tx    <= 1'b0;
                busy  <= 1'b1;
            end
        end else if (baud_counter == CLOCKS_PER_BIT - 1) begin
            baud_counter <= '0;

            if (bit_index == 4'd9) begin
                tx        <= 1'b1;
                busy      <= 1'b0;
                bit_index <= '0;
            end else begin
                bit_index <= bit_index + 1'b1;
                tx        <= frame[bit_index + 1'b1];
            end
        end else begin
            baud_counter <= baud_counter + 1'b1;
        end
    end

endmodule
