# Run from scripts/ after the verified camera pin file has been created:
#   vivado -mode batch -source build_m3_bitstream.tcl

set camera_constraints "../constraints/arty_a7_camera.xdc"
if {![file exists $camera_constraints]} {
    error "Missing $camera_constraints. Copy the template, fill every verified pin/voltage TODO, and review it before building."
}

open_project ../vivado_project/arty_conv.xpr
file mkdir ../docs

if {[llength [get_files -quiet arty_a7_camera.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $camera_constraints
}

set_property top arty_m3_camera_top [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    error "Milestone 3 synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    error "Milestone 3 implementation failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_timing_summary -file ../docs/timing_summary_milestone3.rpt
report_utilization -file ../docs/utilization_milestone3.rpt
report_cdc -details -file ../docs/cdc_milestone3.rpt

set failing_setup_paths [get_timing_paths -quiet -delay_type max -slack_lesser_than 0.0]
if {[llength $failing_setup_paths] != 0} {
    set worst_slack [get_property SLACK [lindex $failing_setup_paths 0]]
    error "Milestone 3 bitstream was generated, but timing failed with worst setup slack $worst_slack ns."
}

puts "Milestone 3 bitstream: [glob ../vivado_project/arty_conv.runs/impl_1/*.bit]"
