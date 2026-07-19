# Synthesizes the M7 top and records pre-route utilization and CDC evidence.
source m7_project_files.tcl
set project_dir ../vivado_project_m7
set project_file $project_dir/arty_conv_m7.xpr
if {[file exists $project_file]} {
    open_project $project_file
} else {
    create_project arty_conv_m7 $project_dir -part xc7a100tcsg324-1
    set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]
}
file mkdir ../artifacts/m7_runs/synthesis
foreach source $m7_design_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -norecurse $source
    }
}
if {[llength [get_files -quiet arty_a7_m5_camera_ethernet.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse ../constraints/arty_a7_m5_camera_ethernet.xdc
}
if {[llength [get_files -quiet arty_a7_m7_timing.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse ../constraints/arty_a7_m7_timing.xdc
}
set_property top arty_m7_camera_ethernet_top [current_fileset]
update_compile_order -fileset sources_1
synth_design -top arty_m7_camera_ethernet_top -part xc7a100tcsg324-1
write_checkpoint -force ../artifacts/m7_runs/synthesis/milestone7_synthesis.dcp
report_utilization -file ../artifacts/m7_runs/synthesis/utilization_milestone7_synthesis.rpt
report_cdc -details -file ../artifacts/m7_runs/synthesis/cdc_milestone7_synthesis.rpt
puts "Milestone 7 synthesis check completed. No hardware benchmark was run."
