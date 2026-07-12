module debounce #(
    parameter integer STABLE_CYCLES = 1_000_000 // 10ms at 100MHz 
) (
    input  logic clk,
    input  logic reset,
    input  logic noisy_in,
    output logic clean_out
);

    localparam integer COUNTER_WIDTH =
        (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);

    (* ASYNC_REG = "TRUE" *) logic [1:0] synchronizer; // Pair of ASYNC FF, will be used for a two stage synchronizer to reduce metastability 
    logic [COUNTER_WIDTH-1:0] stable_counter;

    always_ff @(posedge clk) begin
        if (reset) begin
            synchronizer <= 2'b00; // Reset both syunchronizer FFs to 0
        end else begin
            synchronizer <= {synchronizer[0], noisy_in}; // Normal operation, shift in the new noisy input into the synchronizer
            // new synchronizer[1] = old synchronizer[0]
            // new synchronizer[0] = noisy_in
        end
    end

    generate
        if (STABLE_CYCLES <= 1) begin : g_no_filter_delay // Sync only branch
            always_ff @(posedge clk) begin
                if (reset) begin
                    clean_out     <= 1'b0;
                    stable_counter <= '0;
                end else begin
                    clean_out     <= synchronizer[1]; // Use the second FF output of the synchronizer as the clean output, no filtering needed
                    stable_counter <= '0;
                end
            end
        end else begin : g_filter // Filter branch, requires stable input for STABLE_CYCLES before changing clean_out
            always_ff @(posedge clk) begin
                if (reset) begin
                    clean_out      <= 1'b0;
                    stable_counter <= '0;
                end else if (synchronizer[1] == clean_out) begin
                    stable_counter <= '0;
                end else if (stable_counter == STABLE_CYCLES - 1) begin // If input has been stable for STABLE_CYCLES, update clean_out to match synchronizer[1] -> a press or release has been detected
                    clean_out      <= synchronizer[1];
                    stable_counter <= '0;
                end else begin // Input has changed, but not yet stable for STABLE_CYCLES, increment the counter -> start of a possible press/release
                    stable_counter <= stable_counter + 1'b1;
                end
            end
        end
    endgenerate

endmodule
