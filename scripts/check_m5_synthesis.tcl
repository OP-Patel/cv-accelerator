# Creates the dedicated M5 project and runs synthesis plus a detailed CDC report.
source m5_project_files.tcl
set project_dir ../vivado_project_m5
set project_file $project_dir/arty_conv_m5.xpr
if {[file exists $project_file]} {
    open_project $project_file
} else {
    create_project arty_conv_m5 $project_dir -part xc7a100tcsg324-1
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
write_checkpoint -force ../docs/milestone5_synthesis.dcp
report_utilization -file ../docs/utilization_milestone5_synthesis.rpt
report_cdc -details -file ../docs/cdc_milestone5_synthesis.rpt
puts "Milestone 5 synthesis check completed."
