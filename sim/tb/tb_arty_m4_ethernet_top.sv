`timescale 1ns/1ps
module tb_arty_m4_ethernet_top;
    logic clk_100mhz=0, reset_btn=1, uart_rx=1;
    logic [2:0] btn=0; logic [3:0] sw=0,led;
    logic uart_tx,eth_col,eth_crs,eth_mdc,eth_ref_clk,eth_rstn;
    logic eth_rx_clk,eth_rx_dv,eth_rxerr,eth_tx_clk,eth_tx_en;
    logic [3:0] eth_rxd,eth_txd; tri1 eth_mdio;
    always #5 clk_100mhz=~clk_100mhz;
    arty_m4_ethernet_top #(
        .DEBOUNCE_CYCLES(1),.PHY_RESET_US(1),.PHY_STARTUP_US(1),.UART_BAUD(1_000_000)
    ) u_dut (.*);
    dp83848_mii_model u_phy(
        .ref_clk(eth_ref_clk),.reset_n(eth_rstn),.mdc(eth_mdc),.mdio(eth_mdio),
        .txd(eth_txd),.tx_en(eth_tx_en),.tx_clk(eth_tx_clk),.rx_clk(eth_rx_clk),
        .rxd(eth_rxd),.rx_dv(eth_rx_dv),.rxerr(eth_rxerr),.col(eth_col),.crs(eth_crs)
    );
    initial begin
        repeat(10) @(posedge clk_100mhz); reset_btn=0;
        wait(u_dut.discovery_done);
        if(!u_dut.identity_valid || !u_dut.link_up || !u_dut.speed_100 || !u_dut.full_duplex)
            $fatal(1,"PHY discovery/status failed");
        btn[2]=1; repeat(5) @(posedge clk_100mhz); btn[2]=0;
        wait(u_dut.good_frames!=0);
        if(u_dut.bad_count!=0 || u_dut.drop_count!=0) $fatal(1,"looped frame reported errors");
        $display("PASS: tb_arty_m4_ethernet_top"); $finish;
    end
    initial begin #50_000_000; $fatal(1,"top-level simulation timeout"); end
endmodule
