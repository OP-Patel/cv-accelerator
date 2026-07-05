module uart_tx (
    input  logic clk,
    input  logic reset,
    input  logic [7:0] data,
    input  logic send,
    output logic tx,
    output logic busy
);

    // Milestone 1 placeholder
    assign tx = 1'b1;
    assign busy = 1'b0;

endmodule
