// Emits one fixed-width integrated camera, PHY, and stream status line.
module m5_uart_reporter (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        camera_pass,
    input  logic        network_pass,
    input  logic        stream_pass,
    input  logic [15:0] camera_id,
    input  logic        link_up,
    input  logic        speed_100,
    input  logic        stream_id,
    input  logic [31:0] frame_count,
    input  logic [31:0] packet_count,
    input  logic [31:0] byte_count,
    input  logic [31:0] drop_count,
    input  logic [15:0] error_flags,
    output logic [7:0]  uart_data,
    output logic        uart_send,
    input  logic        uart_busy,
    output logic        busy
);
    localparam integer MESSAGE_LENGTH = 113;
    typedef enum logic [2:0] {IDLE, LOAD, SEND, WAIT_BUSY, WAIT_DONE} state_t;
    state_t state;
    logic [7:0] index;
    logic [MESSAGE_LENGTH*8-1:0] message;

    // Converts one hexadecimal nibble to its printable ASCII character.
    function automatic logic [7:0] hex(input logic [3:0] value);
        hex = (value < 10) ? ("0" + value) : ("A" + value - 10);
    endfunction

    // Converts a 16-bit status value to four printable hexadecimal digits.
    function automatic logic [31:0] hex16(input logic [15:0] value);
        hex16 = {hex(value[15:12]),hex(value[11:8]),hex(value[7:4]),hex(value[3:0])};
    endfunction

    // Converts a 32-bit counter to eight printable hexadecimal digits.
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
                            "[", (camera_pass ? "PASS" : "FAIL"), ":",
                            (network_pass ? "PASS" : "FAIL"), ":",
                            (stream_pass ? "PASS" : "FAIL"), "] M5 CAM=",
                            hex16(camera_id), " LINK=", (link_up ? "1" : "0"),
                            " SPD=", (speed_100 ? "100" : "010"),
                            " MODE=", (stream_id ? "G" : "S"),
                            " F=", hex32(frame_count), " PKT=", hex32(packet_count),
                            " BYTE=", hex32(byte_count), " DROP=", hex32(drop_count),
                            " ERR=", hex16(error_flags), 8'h0d, 8'h0a
                        };
                        index <= '0; busy <= 1'b1; state <= LOAD;
                    end
                end
                LOAD: begin
                    uart_data <= message[MESSAGE_LENGTH*8-1 -: 8];
                    state <= SEND;
                end
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
