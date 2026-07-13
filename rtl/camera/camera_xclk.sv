// Generates the OV7670 24 MHz reference clock and a simple startup sequence.
module camera_xclk #(
    parameter integer STARTUP_CYCLES = 100_000
) (
    input  logic clk_100mhz,
    input  logic reset,
    output logic cam_xclk,
    output logic cam_reset_n,
    output logic cam_pwdn,
    output logic clock_ready
);
    localparam integer STARTUP_W = (STARTUP_CYCLES <= 1) ? 1 : $clog2(STARTUP_CYCLES + 1);

    logic clk_24mhz_mmcm, clk_24mhz;
    logic clk_feedback;
    logic mmcm_locked;
    logic xclk_reset;
    logic [STARTUP_W-1:0] startup_count;

    // 100 MHz * 6 / 25 = 24 MHz. The 600 MHz VCO is valid for Artix-7.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(6.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(25.0),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk_100mhz),
        .RST(reset),
        .PWRDWN(1'b0),
        .CLKFBIN(clk_feedback),
        .CLKFBOUT(clk_feedback),
        .CLKFBOUTB(),
        .CLKOUT0(clk_24mhz_mmcm),
        .LOCKED(mmcm_locked),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    BUFG u_xclk_buffer (
        .I(clk_24mhz_mmcm),
        .O(clk_24mhz)
    );

    // Assert immediately, then release reset on the clock that drives the
    // ODDR. This avoids sending the 100 MHz reset directly into a 24 MHz
    // clocked element.
    reset_sync u_xclk_reset (
        .clk(clk_24mhz),
        .async_reset_in(reset || !mmcm_locked),
        .sync_reset_out(xclk_reset)
    );

    // ODDR places the external clock on a dedicated clock-output path.
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE")
    ) u_xclk_output (
        .C(clk_24mhz),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(xclk_reset),
        .S(1'b0),
        .Q(cam_xclk)
    );

    always_ff @(posedge clk_100mhz) begin
        if (reset || !mmcm_locked) begin
            startup_count <= '0;
            clock_ready   <= 1'b0;
        end else if (!clock_ready) begin
            if (startup_count == STARTUP_CYCLES - 1) begin
                clock_ready <= 1'b1;
            end else begin
                startup_count <= startup_count + 1'b1;
            end
        end
    end

    // Keep the camera inactive until XCLK has been stable for the startup delay.
    assign cam_pwdn    = !clock_ready;
    assign cam_reset_n = clock_ready;
endmodule
