module reset_sync (
    input logic clk, 
    input logic async_reset_in, 
    output logic sync_reset_out
);
    (* ASYNC_REG = "TRUE" *) logic reset_ff1, reset_ff2;

    // Double FFs to reduce metastability, giving ff1 one cycle to settle before ff2 samples it
    always_ff @(posedge clk or posedge async_reset_in) begin
        if (async_reset_in) begin
            reset_ff1 <= 1'b1;
            reset_ff2 <= 1'b1;
        end else begin
            reset_ff1 <= 1'b0;
            reset_ff2 <= reset_ff1;
        end
    end

    assign sync_reset_out = reset_ff2;
endmodule
