## Milestone 7 clock-domain timing exceptions.
##
## The 100 MHz system and 200 MHz processing domains exchange payloads only
## through Xilinx asynchronous FIFOs and explicit toggle synchronizers.
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks core_unbuffered]

## The 24 MHz camera output clock reset is asserted asynchronously and released
## by reset_sync in that clock domain. It is not a system-clock data path.
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks clk_24mhz_mmcm]
