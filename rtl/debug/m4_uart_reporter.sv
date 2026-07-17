// Emits the fixed-width Milestone 4 PHY and packet status line.
module m4_uart_reporter (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        phy_pass,
    input  logic        packet_pass,
    input  logic [15:0] phy_id1,
    input  logic [15:0] phy_id2,
    input  logic        link_up,
    input  logic        speed_100,
    input  logic        full_duplex,
    input  logic [31:0] tx_count,
    input  logic [31:0] rx_count,
    input  logic [31:0] bad_count,
    input  logic [31:0] drop_count,
    input  logic [15:0] error_flags,
    output logic [7:0]  uart_data,
    output logic        uart_send,
    input  logic        uart_busy,
    output logic        busy
);
    localparam integer MESSAGE_LENGTH = 111;
    typedef enum logic [2:0] {IDLE, LOAD, SEND, WAIT_BUSY, WAIT_DONE} state_t;
    state_t state;
    logic [7:0] index;
    logic [MESSAGE_LENGTH*8-1:0] message;

    function automatic logic [7:0] hex(input logic [3:0] value);
        hex = (value < 10) ? ("0" + value) : ("A" + value - 10);
    endfunction
    function automatic logic [31:0] hex16(input logic [15:0] value);
        hex16 = {hex(value[15:12]),hex(value[11:8]),hex(value[7:4]),hex(value[3:0])};
    endfunction
    function automatic logic [63:0] hex32(input logic [31:0] value);
        hex32 = {hex16(value[31:16]),hex16(value[15:0])};
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE; index <= '0; message <= '0;
            uart_data <= '0; uart_send <= 1'b0; busy <= 1'b0;
        end else begin
            uart_send <= 1'b0;
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        message <= {
                            "[", (phy_pass ? "PASS" : "FAIL"), ":",
                            (packet_pass ? "PASS" : "FAIL"), "] M4 PHY=",
                            hex16(phy_id1), ":", hex16(phy_id2), " LINK=",
                            (link_up ? "1" : "0"), " SPD=",
                            (speed_100 ? "100" : "010"), " DUP=",
                            (full_duplex ? "F" : "H"), " TX=", hex32(tx_count),
                            " RX=", hex32(rx_count), " BAD=", hex32(bad_count),
                            " DROP=", hex32(drop_count), " ERR=", hex16(error_flags),
                            8'h0d, 8'h0a
                        };
                        index <= '0; busy <= 1'b1; state <= LOAD;
                    end
                end
                LOAD: begin uart_data <= message[MESSAGE_LENGTH*8-1 -: 8]; state <= SEND; end
                SEND: begin uart_send <= 1'b1; state <= WAIT_BUSY; end
                WAIT_BUSY: if (uart_busy) state <= WAIT_DONE;
                WAIT_DONE: if (!uart_busy) begin
                    if (index == MESSAGE_LENGTH-1) state <= IDLE;
                    else begin
                        index <= index + 1'b1;
                        uart_data <= message[MESSAGE_LENGTH*8-1-((index+1'b1)*8) -: 8];
                        state <= SEND;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
