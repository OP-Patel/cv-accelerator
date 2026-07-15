// Reads the OV7670 identity and writes a documented QVGA RGB565 configuration.
module camera_register_init #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer RESET_DELAY_CYCLES = CLOCK_HZ / 1_000,
    parameter integer SETTLE_CYCLES = (CLOCK_HZ / 10) * 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        test_pattern_enable,
    output logic        command_start,
    output logic        command_write_enable,
    output logic [7:0]  command_register,
    output logic [7:0]  command_write_data,
    input  logic [7:0]  command_read_data,
    input  logic        command_busy,
    input  logic        command_done,
    input  logic        command_ack_error,
    input  logic        command_timeout_error,
    output logic        init_busy,
    output logic        init_done,
    output logic        init_error,
    output logic [15:0] completed_writes,
    output logic [15:0] nack_count,
    output logic [7:0]  product_id,
    output logic [7:0]  version_id
);
    localparam integer DELAY_W = $clog2(((SETTLE_CYCLES > RESET_DELAY_CYCLES) ?
                                         SETTLE_CYCLES : RESET_DELAY_CYCLES) + 1);

    typedef enum logic [3:0] {
        INIT_IDLE,
        ISSUE_RESET,
        WAIT_RESET,
        RESET_DELAY,
        ISSUE_PID,
        WAIT_PID,
        ISSUE_VER,
        WAIT_VER,
        ISSUE_CONFIG,
        WAIT_CONFIG,
        SETTLE_DELAY,
        INIT_FINISHED
    } init_state_t;

    init_state_t state;
    logic [7:0] config_index;
    logic [DELAY_W-1:0] delay_count;
    logic saved_test_pattern;
    logic [15:0] current_entry;

    // Returns a compact table composed from OmniVision's guide and Linux OV7670 driver.
    function automatic logic [15:0] configuration_entry(
        input logic [7:0] index,
        input logic enable_test_pattern
    );
        begin
            case (index)
                // 24 MHz clock, QVGA RGB, active-high VSYNC/HREF, normal byte order.
                0:  configuration_entry = 16'h1101; // CLKRC: 30 fps clock divider.
                1:  configuration_entry = 16'h1214; // COM7: QVGA plus RGB output.
                2:  configuration_entry = 16'h0c04; // COM3: downsample/crop enable.
                3:  configuration_entry = 16'h3e19; // COM14: QVGA DCW and PCLK divide.
                4:  configuration_entry = 16'h703a; // Horizontal scaling factor.
                5:  configuration_entry = 16'h7135; // Vertical scaling factor.
                6:  configuration_entry = 16'h7211; // Downsample by two.
                7:  configuration_entry = 16'h73f1; // Pixel-clock divide by two.
                8:  configuration_entry = 16'ha202; // Pixel-clock delay.
                9:  configuration_entry = 16'h1500; // COM10: documented normal polarities.

                // RGB565 format and full output range.
                10: configuration_entry = 16'h8c00; // Disable RGB444.
                11: configuration_entry = 16'h40d0; // COM15: RGB565, range 00-FF.
                12: configuration_entry = 16'h3a04; // TSLB: normal byte sequencing.

                // Standard OmniVision gamma curve used by the Linux OV7670 driver.
                13: configuration_entry = 16'h7a20;
                14: configuration_entry = 16'h7b10;
                15: configuration_entry = 16'h7c1e;
                16: configuration_entry = 16'h7d35;
                17: configuration_entry = 16'h7e5a;
                18: configuration_entry = 16'h7f69;
                19: configuration_entry = 16'h8076;
                20: configuration_entry = 16'h8180;
                21: configuration_entry = 16'h8288;
                22: configuration_entry = 16'h838f;
                23: configuration_entry = 16'h8496;
                24: configuration_entry = 16'h85a3;
                25: configuration_entry = 16'h86af;
                26: configuration_entry = 16'h87c4;
                27: configuration_entry = 16'h88d7;
                28: configuration_entry = 16'h89e8;

                // Configure AEC/AGC limits before enabling the automatic controls.
                29: configuration_entry = 16'h13e0; // COM8: controls temporarily disabled.
                30: configuration_entry = 16'h0000; // Manual gain seed.
                31: configuration_entry = 16'h1000; // Manual exposure seed.
                32: configuration_entry = 16'h0d40; // COM4: reserved bit required by table.
                33: configuration_entry = 16'h1418; // COM9: 4x gain ceiling.
                34: configuration_entry = 16'ha505; // 50 Hz banding limit.
                35: configuration_entry = 16'hab07; // 60 Hz banding limit.
                36: configuration_entry = 16'h2495; // Stable-exposure upper threshold.
                37: configuration_entry = 16'h2533; // Stable-exposure lower threshold.
                38: configuration_entry = 16'h26e3; // Fast-mode operating region.
                39: configuration_entry = 16'h9f78;
                40: configuration_entry = 16'ha068;
                41: configuration_entry = 16'ha103;
                42: configuration_entry = 16'ha6d8;
                43: configuration_entry = 16'ha7d8;
                44: configuration_entry = 16'ha8f0;
                45: configuration_entry = 16'ha990;
                46: configuration_entry = 16'haa94;
                47: configuration_entry = 16'h13e7; // Enable AEC, AGC, and AWB.

                // RGB color matrix used by the Linux driver's RGB565 mode.
                48: configuration_entry = 16'h4fb3;
                49: configuration_entry = 16'h50b3;
                50: configuration_entry = 16'h5100;
                51: configuration_entry = 16'h523d;
                52: configuration_entry = 16'h53a7;
                53: configuration_entry = 16'h54e4;
                54: configuration_entry = 16'h589e;
                55: configuration_entry = 16'h4108; // Apply AWB gain.
                56: configuration_entry = 16'h3dc0; // Gamma and UV saturation.

                // Explicit Linux-driver QVGA window. The photographed 0x7673
                // sensor otherwise retains a 626-byte-wide reset window.
                57: configuration_entry = 16'h1715; // HSTART: 168 >> 3.
                58: configuration_entry = 16'h1803; // HSTOP: 24 >> 3.
                59: configuration_entry = 16'h3280; // HREF: low start/stop bits.
                60: configuration_entry = 16'h1903; // VSTART: 12 >> 2.
                61: configuration_entry = 16'h1a7b; // VSTOP: 492 >> 2.
                62: configuration_entry = 16'h0300; // VREF: low start/stop bits.

                // COM17 provides the first deterministic hardware test pattern.
                63: configuration_entry = {8'h42, enable_test_pattern ? 8'h08 : 8'h00};
                64: configuration_entry = 16'h1101; // Reapply CLKRC after RGB setup.
                default: configuration_entry = 16'hffff;
            endcase
        end
    endfunction

    assign current_entry = configuration_entry(config_index, saved_test_pattern);

    always_ff @(posedge clk) begin
        if (reset) begin
            state                <= INIT_IDLE;
            config_index         <= '0;
            delay_count          <= '0;
            saved_test_pattern   <= 1'b0;
            command_start        <= 1'b0;
            command_write_enable <= 1'b0;
            command_register     <= '0;
            command_write_data   <= '0;
            init_busy            <= 1'b0;
            init_done            <= 1'b0;
            init_error           <= 1'b0;
            completed_writes     <= '0;
            nack_count           <= '0;
            product_id           <= '0;
            version_id           <= '0;
        end else begin
            command_start <= 1'b0;

            case (state)
                INIT_IDLE, INIT_FINISHED: begin
                    init_busy <= 1'b0;
                    if (start) begin
                        config_index       <= '0;
                        saved_test_pattern <= test_pattern_enable;
                        init_busy          <= 1'b1;
                        init_done          <= 1'b0;
                        init_error         <= 1'b0;
                        completed_writes   <= '0;
                        nack_count         <= '0;
                        product_id         <= '0;
                        version_id         <= '0;
                        state              <= ISSUE_RESET;
                    end
                end

                ISSUE_RESET: begin
                    if (!command_busy) begin
                        command_register     <= 8'h12;
                        command_write_data   <= 8'h80;
                        command_write_enable <= 1'b1;
                        command_start        <= 1'b1;
                        state                <= WAIT_RESET;
                    end
                end

                WAIT_RESET: begin
                    if (command_done) begin
                        if (command_ack_error || command_timeout_error) begin
                            if (command_ack_error) nack_count <= nack_count + 1'b1;
                            init_error <= 1'b1;
                            state <= INIT_FINISHED;
                        end else begin
                            completed_writes <= completed_writes + 1'b1;
                            delay_count <= '0;
                            state <= RESET_DELAY;
                        end
                    end
                end

                RESET_DELAY: begin
                    if (delay_count == RESET_DELAY_CYCLES - 1) begin
                        state <= ISSUE_PID;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                ISSUE_PID: begin
                    if (!command_busy) begin
                        command_register     <= 8'h0a;
                        command_write_enable <= 1'b0;
                        command_start        <= 1'b1;
                        state                <= WAIT_PID;
                    end
                end

                WAIT_PID: begin
                    if (command_done) begin
                        if (command_ack_error || command_timeout_error) begin
                            if (command_ack_error) nack_count <= nack_count + 1'b1;
                            init_error <= 1'b1;
                            state <= INIT_FINISHED;
                        end else begin
                            product_id <= command_read_data;
                            state <= ISSUE_VER;
                        end
                    end
                end

                ISSUE_VER: begin
                    if (!command_busy) begin
                        command_register     <= 8'h0b;
                        command_write_enable <= 1'b0;
                        command_start        <= 1'b1;
                        state                <= WAIT_VER;
                    end
                end

                WAIT_VER: begin
                    if (command_done) begin
                        if (command_ack_error || command_timeout_error) begin
                            if (command_ack_error) nack_count <= nack_count + 1'b1;
                            init_error <= 1'b1;
                            state <= INIT_FINISHED;
                        // OV7670 modules are found with VER=0x70 or VER=0x73.
                        // PID must still be 0x76 so a different sensor is rejected.
                        end else if ((product_id != 8'h76) ||
                                     ((command_read_data != 8'h70) &&
                                      (command_read_data != 8'h73))) begin
                            version_id <= command_read_data;
                            init_error <= 1'b1;
                            state <= INIT_FINISHED;
                        end else begin
                            version_id <= command_read_data;
                            state <= ISSUE_CONFIG;
                        end
                    end
                end

                ISSUE_CONFIG: begin
                    if (current_entry == 16'hffff) begin
                        delay_count <= '0;
                        state <= SETTLE_DELAY;
                    end else if (!command_busy) begin
                        command_register     <= current_entry[15:8];
                        command_write_data   <= current_entry[7:0];
                        command_write_enable <= 1'b1;
                        command_start        <= 1'b1;
                        state                <= WAIT_CONFIG;
                    end
                end

                WAIT_CONFIG: begin
                    if (command_done) begin
                        if (command_ack_error || command_timeout_error) begin
                            if (command_ack_error) nack_count <= nack_count + 1'b1;
                            init_error <= 1'b1;
                            state <= INIT_FINISHED;
                        end else begin
                            completed_writes <= completed_writes + 1'b1;
                            config_index <= config_index + 1'b1;
                            state <= ISSUE_CONFIG;
                        end
                    end
                end

                SETTLE_DELAY: begin
                    if (delay_count == SETTLE_CYCLES - 1) begin
                        init_done <= 1'b1;
                        state <= INIT_FINISHED;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                default: state <= INIT_IDLE;
            endcase
        end
    end
endmodule
