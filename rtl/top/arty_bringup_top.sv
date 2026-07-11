module arty_bringup_top #(
    parameter integer CLOCK_HZ              = 100_000_000,
    parameter integer UART_BAUD             = 115_200,
    parameter integer DEBOUNCE_CYCLES       = 1_000_000,
    parameter integer STATUS_INTERVAL_CYCLES = 500_000_000,
    parameter integer HEARTBEAT_BIT          = 26
) (
    input  logic clk_100mhz,
    input  logic reset_btn,
    input  logic [2:0] btn,
    input  logic [3:0] sw,
    input  logic uart_rx,
    output logic uart_tx,
    output logic [3:0] led
);

    localparam integer STATUS_COUNTER_WIDTH =
        (STATUS_INTERVAL_CYCLES <= 1) ? 1 : $clog2(STATUS_INTERVAL_CYCLES);
    localparam integer INPUT_SETTLE_CYCLES = DEBOUNCE_CYCLES + 3;
    localparam integer INPUT_SETTLE_COUNTER_WIDTH =
        (INPUT_SETTLE_CYCLES <= 1) ? 1 : $clog2(INPUT_SETTLE_CYCLES);
    localparam integer MESSAGE_LENGTH = 14;

    typedef enum logic [2:0] {
        MSG_IDLE,
        MSG_SEND_PULSE,
        MSG_WAIT_BUSY,
        MSG_WAIT_DONE
    } message_state_t;

    logic [26:0] counter;
    logic reset_sync;
    logic [2:0] btn_clean;
    logic [2:0] btn_clean_delayed;
    logic [3:0] sw_clean;
    logic [3:0] message_sw;
    logic [STATUS_COUNTER_WIDTH-1:0] status_counter;
    logic [INPUT_SETTLE_COUNTER_WIDTH-1:0] input_settle_counter;
    logic inputs_ready;
    logic message_pending;
    logic [3:0] message_index;
    message_state_t message_state;

    logic [7:0] uart_data;
    logic uart_send;
    logic uart_busy;

    // Keep the receive pin synchronized and available for later milestones.
    (* ASYNC_REG = "TRUE" *) logic [1:0] uart_rx_sync;

    reset_sync u_reset_sync (
        .clk(clk_100mhz),
        .async_reset_in(reset_btn),
        .sync_reset_out(reset_sync)
    );

    genvar input_index;
    generate
        for (input_index = 0; input_index < 3; input_index = input_index + 1) begin : g_btn_debounce
            debounce #(
                .STABLE_CYCLES(DEBOUNCE_CYCLES)
            ) u_btn_debounce (
                .clk(clk_100mhz),
                .reset(reset_sync),
                .noisy_in(btn[input_index]),
                .clean_out(btn_clean[input_index])
            );
        end

        for (input_index = 0; input_index < 4; input_index = input_index + 1) begin : g_sw_debounce
            debounce #(
                .STABLE_CYCLES(DEBOUNCE_CYCLES)
            ) u_sw_debounce (
                .clk(clk_100mhz),
                .reset(reset_sync),
                .noisy_in(sw[input_index]),
                .clean_out(sw_clean[input_index])
            );
        end
    endgenerate

    uart_tx #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD_RATE(UART_BAUD)
    ) u_uart_tx (
        .clk(clk_100mhz),
        .reset(reset_sync),
        .data(uart_data),
        .send(uart_send),
        .tx(uart_tx),
        .busy(uart_busy)
    );

    function automatic logic [7:0] status_character(
        input logic [3:0] index,
        input logic [3:0] switch_value
    );
        case (index)
            4'd0:  status_character = "M";
            4'd1:  status_character = "1";
            4'd2:  status_character = " ";
            4'd3:  status_character = "O";
            4'd4:  status_character = "K";
            4'd5:  status_character = " ";
            4'd6:  status_character = "S";
            4'd7:  status_character = "W";
            4'd8:  status_character = "=";
            4'd9:  status_character = "0";
            4'd10: status_character = "x";
            4'd11: status_character = (switch_value < 10)
                                            ? ("0" + switch_value)
                                            : ("A" + switch_value - 10);
            4'd12: status_character = 8'h0d;
            4'd13: status_character = 8'h0a;
            default: status_character = " ";
        endcase
    endfunction

    always_ff @(posedge clk_100mhz) begin
        if (reset_sync) begin
            counter <= 27'd0;
            uart_rx_sync <= 2'b11;
        end else begin
            counter <= counter + 27'd1;
            uart_rx_sync <= {uart_rx_sync[0], uart_rx};
        end
    end

    always_ff @(posedge clk_100mhz) begin
        if (reset_sync) begin
            btn_clean_delayed <= '0;
            status_counter    <= '0;
            input_settle_counter <= '0;
            inputs_ready      <= 1'b0;
            message_pending   <= 1'b0;
            message_sw        <= '0;
            message_index     <= '0;
            message_state     <= MSG_IDLE;
            uart_data         <= '0;
            uart_send         <= 1'b0;
        end else begin
            btn_clean_delayed <= btn_clean;
            uart_send <= 1'b0;

            if (!inputs_ready) begin
                if (input_settle_counter == INPUT_SETTLE_CYCLES - 1) begin
                    input_settle_counter <= '0;
                    inputs_ready         <= 1'b1;
                    message_pending      <= 1'b1;
                end else begin
                    input_settle_counter <= input_settle_counter + 1'b1;
                end
            end

            if (STATUS_INTERVAL_CYCLES <= 1 ||
                status_counter == STATUS_INTERVAL_CYCLES - 1) begin
                status_counter  <= '0;
                message_pending <= 1'b1;
            end else begin
                status_counter <= status_counter + 1'b1;
            end

            if (|(btn_clean & ~btn_clean_delayed)) begin
                message_pending <= 1'b1;
            end

            case (message_state)
                MSG_IDLE: begin
                    if (message_pending) begin
                        message_pending <= 1'b0;
                        message_sw      <= sw_clean;
                        message_index   <= '0;
                        uart_data       <= status_character(4'd0, sw_clean);
                        message_state   <= MSG_SEND_PULSE;
                    end
                end

                MSG_SEND_PULSE: begin
                    uart_send     <= 1'b1;
                    message_state <= MSG_WAIT_BUSY;
                end

                MSG_WAIT_BUSY: begin
                    if (uart_busy) begin
                        message_state <= MSG_WAIT_DONE;
                    end
                end

                MSG_WAIT_DONE: begin
                    if (!uart_busy) begin
                        if (message_index == MESSAGE_LENGTH - 1) begin
                            message_state <= MSG_IDLE;
                        end else begin
                            message_index <= message_index + 1'b1;
                            uart_data <= status_character(
                                message_index + 1'b1,
                                message_sw
                            );
                            message_state <= MSG_SEND_PULSE;
                        end
                    end
                end

                default: message_state <= MSG_IDLE;
            endcase
        end
    end

    assign led = reset_sync
        ? 4'b0000
        : {sw_clean[2:0], counter[HEARTBEAT_BIT]};

endmodule
