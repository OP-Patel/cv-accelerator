// Generates the dedicated 200 MHz M7 processing clock from the board clock.
module m7_core_clock (
    input  logic clk_100mhz,
    input  logic reset,
    output logic core_clk,
    output logic locked
);
    wire feedback;
    wire feedback_buffered;
    wire core_unbuffered;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(5.0),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk_100mhz),
        .RST(reset),
        .PWRDWN(1'b0),
        .CLKFBIN(feedback_buffered),
        .CLKFBOUT(feedback),
        .CLKOUT0(core_unbuffered),
        .LOCKED(locked),
        .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );
    BUFG u_feedback_buffer (.I(feedback), .O(feedback_buffered));
    BUFG u_core_buffer (.I(core_unbuffered), .O(core_clk));
endmodule
