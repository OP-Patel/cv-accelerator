// Performs one OV7670 SCCB register read or write at a time.
module sccb_master #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer SCCB_HZ  = 100_000,
    parameter integer TIMEOUT_CYCLES = CLOCK_HZ / 100
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       start,
    input  logic       write_enable,
    input  logic [7:0] register_address,
    input  logic [7:0] write_data,
    output logic [7:0] read_data,
    output logic       busy,
    output logic       done,
    output logic       ack_error,
    output logic       timeout_error,
    output logic       sio_c,
    input  logic       sio_d_in,
    output logic       sio_d_drive_low
);
    localparam integer HALF_PERIOD = CLOCK_HZ / (SCCB_HZ * 2);
    localparam integer DIV_W = (HALF_PERIOD <= 1) ? 1 : $clog2(HALF_PERIOD);
    localparam integer TIMEOUT_W = (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES + 1);
    localparam logic [7:0] DEVICE_WRITE = 8'h42; // 7-bit address 0x21 plus write bit.
    localparam logic [7:0] DEVICE_READ  = 8'h43; // 7-bit address 0x21 plus read bit.

    typedef enum logic [4:0] {
        IDLE,
        START_RELEASE,
        START_DRIVE,
        TX_LOW,
        TX_HIGH,
        ACK_LOW,
        ACK_HIGH,
        MID_STOP_LOW,
        MID_STOP_HIGH,
        MID_STOP_RELEASE,
        READ_LOW,
        READ_HIGH,
        NACK_LOW,
        NACK_HIGH,
        STOP_LOW,
        STOP_HIGH,
        STOP_RELEASE
    } state_t;

    state_t state;
    logic [DIV_W-1:0] divider_count;
    logic [TIMEOUT_W-1:0] timeout_count;
    logic tick;
    logic saved_write_enable;
    logic [7:0] saved_register_address, saved_write_data;
    logic [7:0] transmit_byte, read_shift;
    logic [2:0] bit_index;
    logic [1:0] transmit_stage;

    assign tick = (divider_count == HALF_PERIOD - 1);

    always_ff @(posedge clk) begin
        if (reset) begin
            divider_count <= '0;
        end else if (busy) begin
            if (tick) begin
                divider_count <= '0;
            end else begin
                divider_count <= divider_count + 1'b1;
            end
        end else begin
            divider_count <= '0;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state                  <= IDLE;
            timeout_count          <= '0;
            saved_write_enable     <= 1'b0;
            saved_register_address <= '0;
            saved_write_data       <= '0;
            transmit_byte          <= '0;
            read_shift             <= '0;
            read_data              <= '0;
            bit_index              <= '0;
            transmit_stage         <= '0;
            busy                   <= 1'b0;
            done                   <= 1'b0;
            ack_error              <= 1'b0;
            timeout_error          <= 1'b0;
            sio_c                  <= 1'b1;
            sio_d_drive_low        <= 1'b0;
        end else begin
            done <= 1'b0;

            if (busy && !timeout_error) begin
                if (timeout_count == TIMEOUT_CYCLES - 1) begin
                    timeout_error   <= 1'b1;
                    state           <= STOP_LOW;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end

            if (!busy && start) begin
                saved_write_enable     <= write_enable;
                saved_register_address <= register_address;
                saved_write_data       <= write_data;
                transmit_byte          <= DEVICE_WRITE;
                transmit_stage         <= 2'd0;
                bit_index              <= 3'd7;
                timeout_count          <= '0;
                ack_error              <= 1'b0;
                timeout_error          <= 1'b0;
                busy                   <= 1'b1;
                state                  <= START_RELEASE;
            end else if (busy && tick &&
                         ((timeout_error && ((state == STOP_LOW) ||
                                            (state == STOP_HIGH) ||
                                            (state == STOP_RELEASE))) ||
                          (!timeout_error && (timeout_count != TIMEOUT_CYCLES - 1)))) begin
                case (state)
                    START_RELEASE: begin
                        sio_c           <= 1'b1;
                        sio_d_drive_low <= 1'b0;
                        state           <= START_DRIVE;
                    end

                    START_DRIVE: begin
                        sio_c           <= 1'b1;
                        sio_d_drive_low <= 1'b1;
                        state           <= TX_LOW;
                    end

                    TX_LOW: begin
                        sio_c           <= 1'b0;
                        sio_d_drive_low <= !transmit_byte[bit_index];
                        state           <= TX_HIGH;
                    end

                    TX_HIGH: begin
                        sio_c <= 1'b1;
                        if (bit_index == 0) begin
                            state <= ACK_LOW;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state <= TX_LOW;
                        end
                    end

                    ACK_LOW: begin
                        sio_c           <= 1'b0;
                        sio_d_drive_low <= 1'b0;
                        state           <= ACK_HIGH;
                    end

                    ACK_HIGH: begin
                        sio_c <= 1'b1;
                        if (sio_d_in == 1'b1) begin
                            ack_error <= 1'b1;
                            state <= STOP_LOW;
                        end else if (transmit_stage == 0) begin
                            transmit_stage <= 2'd1;
                            transmit_byte  <= saved_register_address;
                            bit_index      <= 3'd7;
                            state          <= TX_LOW;
                        end else if (transmit_stage == 1) begin
                            if (saved_write_enable) begin
                                transmit_stage <= 2'd2;
                                transmit_byte  <= saved_write_data;
                                bit_index      <= 3'd7;
                                state          <= TX_LOW;
                            end else begin
                                state <= MID_STOP_LOW;
                            end
                        end else if (saved_write_enable) begin
                            state <= STOP_LOW;
                        end else begin
                            bit_index  <= 3'd7;
                            read_shift <= '0;
                            state      <= READ_LOW;
                        end
                    end

                    // End the register-address phase before starting the SCCB read phase.
                    MID_STOP_LOW: begin
                        sio_c           <= 1'b0;
                        sio_d_drive_low <= 1'b1;
                        state           <= MID_STOP_HIGH;
                    end

                    MID_STOP_HIGH: begin
                        sio_c <= 1'b1;
                        state <= MID_STOP_RELEASE;
                    end

                    MID_STOP_RELEASE: begin
                        sio_d_drive_low <= 1'b0;
                        transmit_stage  <= 2'd2;
                        transmit_byte   <= DEVICE_READ;
                        bit_index       <= 3'd7;
                        state           <= START_RELEASE;
                    end

                    READ_LOW: begin
                        sio_c           <= 1'b0;
                        sio_d_drive_low <= 1'b0;
                        state           <= READ_HIGH;
                    end

                    READ_HIGH: begin
                        sio_c <= 1'b1;
                        read_shift[bit_index] <= sio_d_in;
                        if (bit_index == 0) begin
                            read_data <= {read_shift[7:1], sio_d_in};
                            state <= NACK_LOW;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state <= READ_LOW;
                        end
                    end

                    // A released SDA is the master's NACK after the final read byte.
                    NACK_LOW: begin
                        sio_c           <= 1'b0;
                        sio_d_drive_low <= 1'b0;
                        state           <= NACK_HIGH;
                    end

                    NACK_HIGH: begin
                        sio_c <= 1'b1;
                        state <= STOP_LOW;
                    end

                    STOP_LOW: begin
                        sio_c           <= 1'b0;
                        sio_d_drive_low <= 1'b1;
                        state           <= STOP_HIGH;
                    end

                    STOP_HIGH: begin
                        sio_c <= 1'b1;
                        state <= STOP_RELEASE;
                    end

                    STOP_RELEASE: begin
                        sio_d_drive_low <= 1'b0;
                        busy            <= 1'b0;
                        done            <= 1'b1;
                        state           <= IDLE;
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

    initial begin
        if (HALF_PERIOD < 2) begin
            $error("CLOCK_HZ must be at least four times SCCB_HZ");
        end
    end
endmodule
