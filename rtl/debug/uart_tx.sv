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
    logic [3:0] bit_index; // start, data, stop bits
    logic [9:0] frame; // 10 bit uart framed

    always_ff @(posedge clk) begin
        if (reset) begin
            tx           <= 1'b1;
            busy         <= 1'b0;
            baud_counter <= '0;
            bit_index    <= '0;
            frame        <= 10'h3ff; // 10 1s, idle state
        end else if (!busy) begin
            tx           <= 1'b1;
            baud_counter <= '0;
            bit_index    <= '0;

            if (send) begin
                frame <= {1'b1, data, 1'b0}; // Start bit, data byte, stop bit
                tx    <= 1'b0; // immediately starts the start bit for TX
                busy  <= 1'b1; // announce its occupied and will be busy for the next 10 bits
            end
        end else if (baud_counter == CLOCKS_PER_BIT - 1) begin // while busy is high, we are in the middle of sending a frame, so we need to count out the baud rate and send the next bit when the counter reaches the end of the baud period
            baud_counter <= '0;

            if (bit_index == 4'd9) begin // TX represents the stop bit (9th bit), so when we are done sending the stop bit, we can go back to idle state
                tx        <= 1'b1;
                busy      <= 1'b0;
                bit_index <= '0;
            end else begin // ELSE, if its not the 9th bit, we are still in the middle of sending the frame, so we need to increment the bit index and send the next bit in the frame
                bit_index <= bit_index + 1'b1;
                tx        <= frame[bit_index + 1'b1];
            end
        end else begin
            baud_counter <= baud_counter + 1'b1; // still sending the current bit, no need to increment the bit index, just increment the baud counter to keep track of how long we have been sending this bit
        end
    end

endmodule
