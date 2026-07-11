module debounce #(
    parameter integer STABLE_CYCLES = 1_000_000
) (
    input  logic clk,
    input  logic reset,
    input  logic noisy_in,
    output logic clean_out
);

    localparam integer COUNTER_WIDTH =
        (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);

    (* ASYNC_REG = "TRUE" *) logic [1:0] synchronizer;
    logic [COUNTER_WIDTH-1:0] stable_counter;

    always_ff @(posedge clk) begin
        if (reset) begin
            synchronizer <= 2'b00;
        end else begin
            synchronizer <= {synchronizer[0], noisy_in};
        end
    end

    generate
        if (STABLE_CYCLES <= 1) begin : g_no_filter_delay
            always_ff @(posedge clk) begin
                if (reset) begin
                    clean_out     <= 1'b0;
                    stable_counter <= '0;
                end else begin
                    clean_out     <= synchronizer[1];
                    stable_counter <= '0;
                end
            end
        end else begin : g_filter
            always_ff @(posedge clk) begin
                if (reset) begin
                    clean_out      <= 1'b0;
                    stable_counter <= '0;
                end else if (synchronizer[1] == clean_out) begin
                    stable_counter <= '0;
                end else if (stable_counter == STABLE_CYCLES - 1) begin
                    clean_out      <= synchronizer[1];
                    stable_counter <= '0;
                end else begin
                    stable_counter <= stable_counter + 1'b1;
                end
            end
        end
    endgenerate

endmodule
