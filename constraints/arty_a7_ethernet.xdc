## Arty A7-100T system clock and controls
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports {clk_100mhz}]
create_clock -name sys_clk -period 10.000 -waveform {0.000 5.000} [get_ports {clk_100mhz}]
set_property -dict { PACKAGE_PIN D9 IOSTANDARD LVCMOS33 } [get_ports {reset_btn}]
set_property -dict { PACKAGE_PIN C9 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN B9 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN B8 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN A9 IOSTANDARD LVCMOS33 } [get_ports {uart_rx}]
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports {uart_tx}]
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN T9 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## DP83848J 10/100 PHY in 4-bit MII mode (Digilent Arty A7 Master XDC)
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports {eth_col}]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports {eth_crs}]
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports {eth_mdc}]
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {eth_mdio}]
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_ref_clk}]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports {eth_rstn}]
set_property -dict { PACKAGE_PIN F15 IOSTANDARD LVCMOS33 } [get_ports {eth_rx_clk}]
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports {eth_rx_dv}]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[0]}]
set_property -dict { PACKAGE_PIN E17 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[1]}]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[2]}]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[3]}]
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports {eth_rxerr}]
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports {eth_tx_clk}]
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_tx_en}]
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[0]}]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[2]}]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[3]}]

## Maximum-rate (100 Mb/s) MII clocks. The same logic naturally follows the
## PHY's 2.5 MHz TX/RX clocks after a 10 Mb/s negotiation.
create_clock -name eth_rx_clk_in -period 40.000 -waveform {0.000 20.000} [get_ports {eth_rx_clk}]
create_clock -name eth_tx_clk_in -period 40.000 -waveform {0.000 20.000} [get_ports {eth_tx_clk}]
create_generated_clock -name eth_ref_clk_out -source [get_ports {clk_100mhz}] -divide_by 4 [get_ports {eth_ref_clk}]

## DP83848 100-Mb/s receive clock-to-output is 10..30 ns. Capturing on the
## following rising edge leaves the correct full-cycle relationship.
set_input_delay -clock eth_rx_clk_in -min 10.000 [get_ports {eth_rxd[*] eth_rx_dv eth_rxerr}]
set_input_delay -clock eth_rx_clk_in -max 30.000 [get_ports {eth_rxd[*] eth_rx_dv eth_rxerr}]

## The PHY samples MII transmit signals on TX_CLK falling edges and requires
## 9.7 ns setup at 100 Mb/s. FPGA outputs are launched on rising edges.
set_output_delay -clock eth_tx_clk_in -clock_fall -max 9.700 [get_ports {eth_txd[*] eth_tx_en}]
set_output_delay -clock eth_tx_clk_in -clock_fall -min 0.000 [get_ports {eth_txd[*] eth_tx_en}]

set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks eth_rx_clk_in] -group [get_clocks eth_tx_clk_in]
# Arty A7 configuration bank is powered at 3.3 V.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
