# Builds the Arty A7-100T DP83848 10/100 Ethernet bitstream.
open_project ../vivado_project/arty_conv.xpr
file mkdir ../docs
set_property top arty_m4_ethernet_top [current_fileset]
foreach old_xdc {arty_a7_video.xdc arty_a7_camera.xdc} {
    if {[llength [get_files -quiet $old_xdc]] != 0} {
        set_property IS_ENABLED false [get_files $old_xdc]
    }
}
if {[llength [get_files -quiet arty_a7_ethernet.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse ../constraints/arty_a7_ethernet.xdc
}
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    error "Milestone 4 synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    error "Milestone 4 implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_timing_summary -file ../docs/timing_summary_milestone4.rpt
report_utilization -file ../docs/utilization_milestone4.rpt
report_cdc -details -file ../docs/cdc_milestone4.rpt
report_drc -file ../docs/drc_milestone4.rpt
set failing_paths [get_timing_paths -quiet -slack_lesser_than 0.0]
if {[llength $failing_paths] != 0} {
    error "Milestone 4 timing failed; see docs/timing_summary_milestone4.rpt"
}
set bitstream [lindex [glob ../vivado_project/arty_conv.runs/impl_1/*.bit] 0]
set digest [exec certutil -hashfile $bitstream SHA256]
set handle [open ../docs/milestone4_bitstream_sha256.txt w]
puts $handle $digest
close $handle
puts "Milestone 4 bitstream: $bitstream"
