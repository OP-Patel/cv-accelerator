# Programs the first attached Arty A7-100T with the timing-clean M7 image.
set script_dir [file dirname [file normalize [info script]]]
set repository_dir [file dirname $script_dir]
set bitstream [file join $repository_dir artifacts m7_runs build arty_m7_camera_ethernet_top.bit]
if {![file exists $bitstream]} {
    error "Milestone 7 bitstream does not exist: $bitstream"
}

open_hw_manager
connect_hw_server
open_hw_target

set devices [get_hw_devices -quiet]
if {[llength $devices] != 1} {
    error "Expected one attached FPGA, found [llength $devices]: $devices"
}

set device [lindex $devices 0]
set part [get_property PART $device]
if {![string match -nocase *7a100t* $part]} {
    error "Attached FPGA is $part, not the expected Arty A7-100T"
}

set_property PROGRAM.FILE $bitstream $device
set_property PROBES.FILE {} $device
puts "Programming $device ($part) with $bitstream"
program_hw_devices $device
refresh_hw_device -update_hw_probes false $device
puts "CONFIG_STATUS=[get_property REGISTER.CONFIG_STATUS $device]"
puts "PROGRAM_FILE=[get_property PROGRAM.FILE $device]"

close_hw_target
disconnect_hw_server
close_hw_manager
