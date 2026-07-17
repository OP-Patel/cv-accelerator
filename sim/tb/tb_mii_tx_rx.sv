`timescale 1ns/1ps
module tb_mii_tx_rx;
    logic clk=0, reset=1, valid=0, last=0;
    logic [7:0] tx_byte=0, rx_byte;
    logic ready, tx_en, underrun, rx_valid, frame_start, frame_end, rx_error, odd;
    logic [3:0] txd;
    logic [7:0] received[0:3]; integer count=0;
    always #20 clk=~clk;
    mii_tx u_tx(.tx_clk(clk),.reset(reset),.byte_data(tx_byte),.byte_valid(valid),
        .byte_last(last),.byte_ready(ready),.eth_txd(txd),.eth_tx_en(tx_en),.underrun(underrun));
    mii_rx u_rx(.rx_clk(clk),.reset(reset),.eth_rxd(txd),.eth_rx_dv(tx_en),.eth_rxerr(1'b0),
        .byte_data(rx_byte),.byte_valid(rx_valid),.frame_start(frame_start),.frame_end(frame_end),
        .rx_error(rx_error),.odd_nibble(odd));
    always @(negedge clk) if(rx_valid) begin received[count]=rx_byte; count=count+1; end
    task automatic send(input logic [7:0] value,input logic is_last);
        begin wait(ready); @(negedge clk); tx_byte=value; last=is_last; valid=1; @(negedge clk); valid=0; wait(ready); end
    endtask
    initial begin
        repeat(3) @(posedge clk); reset=0;
        send(8'h12,0); send(8'hAB,0); send(8'h05,1);
        wait(frame_end); repeat(2) @(posedge clk);
        if(count!=3 || received[0]!=8'h12 || received[1]!=8'hAB || received[2]!=8'h05)
            $fatal(1,"MII nibble reconstruction failed count=%0d",count);
        if(underrun || rx_error || odd) $fatal(1,"unexpected MII error");
        $display("PASS: tb_mii_tx_rx"); $finish;
    end
endmodule
