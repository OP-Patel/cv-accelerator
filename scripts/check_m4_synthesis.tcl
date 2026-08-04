# Elaborates/synthesizes the 10/100 Ethernet top without generating a bitstream.
source m4_project_files.tcl
set project_dir ../vivado_project
set project_name arty_conv
set project_file $project_dir/$project_name.xpr
if {[file exists ../vivado_project/arty_conv.xpr]} {
    open_project $project_file
} else {
    set project_dir ../vivado_project_m4
    set project_name arty_conv_m4
    set project_file $project_dir/$project_name.xpr
    if {[file exists $project_file]} {
        open_project $project_file
    } else {
        create_project $project_name $project_dir -part xc7a100tcsg324-1
        set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]
    }
}
file mkdir ../docs
foreach source $m4_design_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -norecurse $source
    }
}
set_property top arty_m4_ethernet_top [current_fileset]
if {[get_property top [current_fileset]] ne "arty_m4_ethernet_top"} {
    error "Could not select arty_m4_ethernet_top."
}
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
open_run synth_1
report_utilization -file ../docs/utilization_milestone4_synthesis.rpt
report_cdc -details -file ../docs/cdc_milestone4_synthesis.rpt
puts "Milestone 4 synthesis check completed."
