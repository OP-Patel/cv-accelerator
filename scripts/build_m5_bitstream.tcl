# Builds the pin-complete integrated camera-over-Ethernet bitstream.
source m5_project_files.tcl
set project_dir ../vivado_project_m5
set project_name arty_conv_m5
set project_file $project_dir/$project_name.xpr
if {[file exists $project_file]} {
    open_project $project_file
} else {
    create_project $project_name $project_dir -part xc7a100tcsg324-1
    set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]
}
file mkdir ../docs
foreach source $m5_design_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -norecurse $source
    }
}
if {[llength [get_files -quiet arty_a7_m5_camera_ethernet.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse ../constraints/arty_a7_m5_camera_ethernet.xdc
}
set_property top arty_m5_camera_ethernet_top [current_fileset]
update_compile_order -fileset sources_1
synth_design -top arty_m5_camera_ethernet_top -part xc7a100tcsg324-1
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file ../docs/timing_summary_milestone5.rpt
report_utilization -file ../docs/utilization_milestone5.rpt
report_cdc -details -file ../docs/cdc_milestone5.rpt
report_drc -file ../docs/drc_milestone5.rpt
set failing_paths [get_timing_paths -quiet -slack_lesser_than 0.0]
if {[llength $failing_paths] != 0} {
    error "Milestone 5 timing failed; see docs/timing_summary_milestone5.rpt"
}
file mkdir $project_dir/$project_name.runs/impl_1
set bitstream $project_dir/$project_name.runs/impl_1/arty_m5_camera_ethernet_top.bit
write_checkpoint -force $project_dir/$project_name.runs/impl_1/arty_m5_camera_ethernet_top_routed.dcp
write_bitstream -force $bitstream
set digest [exec certutil -hashfile $bitstream SHA256]
set handle [open ../docs/milestone5_bitstream_sha256.txt w]
puts $handle $digest
close $handle
puts "Milestone 5 bitstream: $bitstream"
