// Generates and forwards the DP83848's required 25 MHz reference clock.
module ethernet_ref_clock (
    input  logic clk_100mhz,
    input  logic reset,
    output logic eth_ref_clk,
    output logic clock_ready
);
    logic clk_25mhz_mmcm, clk_25mhz, clk_feedback, mmcm_locked;
    logic output_reset;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(8.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(32.0),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk_100mhz), .RST(reset), .PWRDWN(1'b0),
        .CLKFBIN(clk_feedback), .CLKFBOUT(clk_feedback), .CLKFBOUTB(),
        .CLKOUT0(clk_25mhz_mmcm), .LOCKED(mmcm_locked),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    BUFG u_ref_buffer (.I(clk_25mhz_mmcm), .O(clk_25mhz));

    reset_sync u_output_reset (
        .clk(clk_25mhz), .async_reset_in(reset || !mmcm_locked),
        .sync_reset_out(output_reset)
    );

    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_ref_output (
        .C(clk_25mhz), .CE(1'b1), .D1(1'b1), .D2(1'b0),
        .R(output_reset), .S(1'b0), .Q(eth_ref_clk)
    );

    always_ff @(posedge clk_100mhz) begin
        if (reset) clock_ready <= 1'b0;
        else       clock_ready <= mmcm_locked;
    end
endmodule
