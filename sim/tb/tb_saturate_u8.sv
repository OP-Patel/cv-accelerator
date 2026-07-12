`timescale 1ns/1ps

// Exhaustively checks every value accepted by the 11-bit saturator.
module tb_saturate_u8;
    logic [10:0] in_value;
    logic [7:0] out_value;
    integer value;

    saturate_u8 u_dut (.in_value(in_value), .out_value(out_value));

    initial begin
        for (value = 0; value < 2048; value = value + 1) begin
            in_value = value;
            #1;
            if (out_value !== (value > 255 ? 8'd255 : value[7:0])) begin
                $fatal(1, "saturation mismatch: input=%0d output=%0d", value, out_value);
            end
        end
        $display("PASS: tb_saturate_u8 checked all 2048 inputs");
        $finish;
    end
endmodule
