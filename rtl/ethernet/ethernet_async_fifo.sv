// Small dual-clock FIFO for complete {last,byte} transmit records.
module ethernet_async_fifo #(
    parameter integer WIDTH = 9,
    parameter integer DEPTH = 2048
) (
    input  logic             reset,
    input  logic             write_clk,
    input  logic             write_enable,
    input  logic [WIDTH-1:0] write_data,
    output logic             full,
    output logic             overflow,
    input  logic             read_clk,
    input  logic             read_enable,
    output logic [WIDTH-1:0] read_data,
    output logic             empty,
    output logic             underflow
);
    localparam integer ADDR_W = $clog2(DEPTH);
    logic [WIDTH-1:0] memory [0:DEPTH-1];
    logic [ADDR_W:0] write_binary, write_gray, read_binary, read_gray;
    (* ASYNC_REG = "TRUE" *) logic [ADDR_W:0] read_gray_sync1, read_gray_sync2;
    (* ASYNC_REG = "TRUE" *) logic [ADDR_W:0] write_gray_sync1, write_gray_sync2;
    logic [ADDR_W:0] write_binary_next, write_gray_next, read_binary_next, read_gray_next;

    assign write_binary_next = write_binary + (write_enable && !full);
    assign write_gray_next = (write_binary_next >> 1) ^ write_binary_next;
    assign read_binary_next = read_binary + (read_enable && !empty);
    assign read_gray_next = (read_binary_next >> 1) ^ read_binary_next;
    assign full = write_gray_next == {~read_gray_sync2[ADDR_W:ADDR_W-1], read_gray_sync2[ADDR_W-2:0]};
    assign empty = read_gray == write_gray_sync2;
    assign read_data = memory[read_binary[ADDR_W-1:0]];

    initial begin
        if ((1 << ADDR_W) != DEPTH) $error("ethernet_async_fifo DEPTH must be a power of two");
    end

    always_ff @(posedge write_clk or posedge reset) begin
        if (reset) begin
            write_binary <= '0; write_gray <= '0;
            read_gray_sync1 <= '0; read_gray_sync2 <= '0; overflow <= 1'b0;
        end else begin
            read_gray_sync1 <= read_gray; read_gray_sync2 <= read_gray_sync1;
            if (write_enable && !full) begin
                memory[write_binary[ADDR_W-1:0]] <= write_data;
                write_binary <= write_binary_next; write_gray <= write_gray_next;
            end else if (write_enable) overflow <= 1'b1;
        end
    end

    always_ff @(posedge read_clk or posedge reset) begin
        if (reset) begin
            read_binary <= '0; read_gray <= '0;
            write_gray_sync1 <= '0; write_gray_sync2 <= '0; underflow <= 1'b0;
        end else begin
            write_gray_sync1 <= write_gray; write_gray_sync2 <= write_gray_sync1;
            if (read_enable && !empty) begin
                read_binary <= read_binary_next; read_gray <= read_gray_next;
            end else if (read_enable) underflow <= 1'b1;
        end
    end
endmodule
