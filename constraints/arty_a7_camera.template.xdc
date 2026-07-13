## Milestone 3 OV7670 camera constraints TEMPLATE.
##
## Do not rename this file to arty_a7_camera.xdc until the physical module,
## voltage compatibility, connector orientation, and every package pin below
## have been verified. The Milestone 3 build script intentionally refuses to
## generate a bitstream without that reviewed file.

## Proposed two-Pmod assignment for the Arty A7-100T.
##
## Camera data uses high-speed header JC. Timing and control use high-speed
## header JB, with PCLK on the clock-capable JB1 input. The package pins below
## come from Digilent's Arty-A7-100 Master XDC. Keep these lines commented until
## the camera module voltage levels and connector orientation are verified.
##
## Camera  Arty header  FPGA package pin
## PLK     JB1          E15
## VS      JB2          E16
## HS      JB3          D15
## XLK     JB4          C15
## SCL     JB7          J17
## SDA     JB8          J18
## RET     JB9          K15
## PWDN    JB10         J15
## D0      JC1          U12
## D1      JC2          V12
## D2      JC3          V10
## D3      JC4          V11
## D4      JC7          U14
## D5      JC8          V14
## D6      JC9          T13
## D7      JC10         U13
##
## Each Pmod header supplies GND on pins 5 and 11 and 3.3 V on pins 6 and 12.
## Do not connect those power pins until the exact breakout is proven safe at
## 3.3 V and its current requirement is known.

# set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports cam_pclk]       ; # JB1  <- PLK
# set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports cam_vsync]      ; # JB2  <- VS
# set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports cam_href]       ; # JB3  <- HS
# set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {cam_d[0]}]     ; # JC1  <- D0
# set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {cam_d[1]}]     ; # JC2  <- D1
# set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {cam_d[2]}]     ; # JC3  <- D2
# set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {cam_d[3]}]     ; # JC4  <- D3
# set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {cam_d[4]}]     ; # JC7  <- D4
# set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {cam_d[5]}]     ; # JC8  <- D5
# set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports {cam_d[6]}]     ; # JC9  <- D6
# set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {cam_d[7]}]     ; # JC10 <- D7
# set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW FAST } [get_ports cam_xclk]    ; # JB4  -> XLK
# set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW } [get_ports cam_reset_n] ; # JB9  -> RET
# set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW } [get_ports cam_pwdn]    ; # JB10 -> PWDN
# set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW } [get_ports cam_sio_c]   ; # JB7  -> SCL
# set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 DRIVE 4 PULLUP TRUE } [get_ports cam_sio_d] ; # JB8 <-> SDA

## Replace 41.667 ns with the maximum measured/configured PCLK period if needed.
# create_clock -name cam_pclk -period 41.667 -waveform {0.000 20.833} [get_ports cam_pclk]
# set_clock_groups -asynchronous -group [get_clocks sys_clk_pin] -group [get_clocks cam_pclk]
# set_false_path -to [get_pins {u_camera_clock/u_xclk_reset/reset_ff1_reg/PRE u_camera_clock/u_xclk_reset/reset_ff2_reg/PRE u_camera_reset/reset_ff1_reg/PRE u_camera_reset/reset_ff2_reg/PRE}]

## Derive final input delays from the OV7670 timing, measured PCLK, and wiring
## skew. Do not uncomment guessed numbers merely to silence timing warnings.
# set_input_delay -clock cam_pclk -max <DERIVED_MAX_NS> [get_ports {cam_d[*] cam_vsync cam_href}]
# set_input_delay -clock cam_pclk -min <DERIVED_MIN_NS> [get_ports {cam_d[*] cam_vsync cam_href}]
