// Holds the PHY in hardware reset, then allows its clocks/straps to settle.
module phy_reset #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer RESET_US = 10_000,
    parameter integer STARTUP_US = 10_000
) (
    input  logic clk,
    input  logic reset,
    input  logic restart,
    input  logic ref_clock_ready,
    output logic eth_rstn,
    output logic ready
);
    localparam integer RESET_CYCLES = (CLOCK_HZ / 1_000_000) * RESET_US;
    localparam integer STARTUP_CYCLES = (CLOCK_HZ / 1_000_000) * STARTUP_US;
    localparam integer MAX_CYCLES = (RESET_CYCLES > STARTUP_CYCLES) ? RESET_CYCLES : STARTUP_CYCLES;
    localparam integer COUNT_W = (MAX_CYCLES <= 1) ? 1 : $clog2(MAX_CYCLES + 1);
    typedef enum logic [1:0] {HOLD_RESET, WAIT_STARTUP, PHY_READY} state_t;
    state_t state;
    logic [COUNT_W-1:0] count;

    always_ff @(posedge clk) begin
        if (reset || restart || !ref_clock_ready) begin
            state <= HOLD_RESET;
            count <= '0;
            eth_rstn <= 1'b0;
            ready <= 1'b0;
        end else begin
            case (state)
                HOLD_RESET: begin
                    eth_rstn <= 1'b0;
                    if ((RESET_CYCLES <= 1) || (count == RESET_CYCLES - 1)) begin
                        count <= '0;
                        eth_rstn <= 1'b1;
                        state <= WAIT_STARTUP;
                    end else count <= count + 1'b1;
                end
                WAIT_STARTUP: begin
                    eth_rstn <= 1'b1;
                    if ((STARTUP_CYCLES <= 1) || (count == STARTUP_CYCLES - 1)) begin
                        ready <= 1'b1;
                        state <= PHY_READY;
                    end else count <= count + 1'b1;
                end
                default: begin
                    eth_rstn <= 1'b1;
                    ready <= 1'b1;
                end
            endcase
        end
    end
endmodule
