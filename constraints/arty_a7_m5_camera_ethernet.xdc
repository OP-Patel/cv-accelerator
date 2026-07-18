## Milestone 5 combined Arty A7-100T, OV7670, and DP83848J constraints.

## 100 MHz board clock, buttons, switches, LEDs, and USB-UART.
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports clk_100mhz]
create_clock -name sys_clk -period 10.000 -waveform {0.000 5.000} [get_ports clk_100mhz]
set_property -dict { PACKAGE_PIN D9 IOSTANDARD LVCMOS33 } [get_ports reset_btn]
set_property -dict { PACKAGE_PIN C9 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN B9 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN B8 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN A9 IOSTANDARD LVCMOS33 } [get_ports uart_rx]
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN T9 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## Direct-DVP OV7670 on the photographed JB/JC wiring used for Milestone 3.
set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports cam_pclk]
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports cam_vsync]
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports cam_href]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {cam_d[0]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {cam_d[1]}]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {cam_d[2]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {cam_d[3]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {cam_d[4]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {cam_d[5]}]
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports {cam_d[6]}]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {cam_d[7]}]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW FAST } [get_ports cam_xclk]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW } [get_ports cam_reset_n]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW } [get_ports cam_pwdn]
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW } [get_ports cam_sio_c]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 DRIVE 4 PULLUP TRUE } [get_ports cam_sio_d]
create_clock -name cam_pclk -period 41.667 -waveform {0.000 20.833} [get_ports cam_pclk]

## DP83848J 4-bit MII pins from the Digilent Arty A7 master constraints.
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports eth_col]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports eth_crs]
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports eth_mdc]
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports eth_mdio]
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports eth_ref_clk]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports eth_rstn]
set_property -dict { PACKAGE_PIN F15 IOSTANDARD LVCMOS33 } [get_ports eth_rx_clk]
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports eth_rx_dv]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[0]}]
set_property -dict { PACKAGE_PIN E17 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[1]}]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[2]}]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[3]}]
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports eth_rxerr]
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports eth_tx_clk]
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports eth_tx_en]
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[0]}]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[2]}]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports {eth_txd[3]}]

## Maximum-rate MII timing. The logic naturally follows 2.5 MHz at 10 Mb/s.
create_clock -name eth_rx_clk_in -period 40.000 -waveform {0.000 20.000} [get_ports eth_rx_clk]
create_clock -name eth_tx_clk_in -period 40.000 -waveform {0.000 20.000} [get_ports eth_tx_clk]
create_generated_clock -name eth_ref_clk_out -source [get_ports clk_100mhz] -divide_by 4 [get_ports eth_ref_clk]
set_input_delay -clock eth_rx_clk_in -min 10.000 [get_ports {eth_rxd[*] eth_rx_dv eth_rxerr}]
set_input_delay -clock eth_rx_clk_in -max 30.000 [get_ports {eth_rxd[*] eth_rx_dv eth_rxerr}]
set_output_delay -clock eth_tx_clk_in -clock_fall -max 9.700 [get_ports {eth_txd[*] eth_tx_en}]
set_output_delay -clock eth_tx_clk_in -clock_fall -min 0.000 [get_ports {eth_txd[*] eth_tx_en}]

## Camera, system, and PHY-provided clocks are independent domains.
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks cam_pclk] \
    -group [get_clocks eth_rx_clk_in] \
    -group [get_clocks eth_tx_clk_in]

## Reset assertion is asynchronous; each named synchronizer makes release local.
set_false_path -to [get_pins {
    u_camera_clock/u_xclk_reset/reset_ff1_reg/PRE
    u_camera_clock/u_xclk_reset/reset_ff2_reg/PRE
    u_camera_reset/reset_ff1_reg/PRE
    u_camera_reset/reset_ff2_reg/PRE
}]

## DVP input delays remain intentionally unguessed pending measured cable skew.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
