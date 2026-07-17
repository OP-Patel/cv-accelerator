# Elaborates/synthesizes the 10/100 Ethernet top without generating a bitstream.
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
open_run synth_1
report_utilization -file ../docs/utilization_milestone4_synthesis.rpt
report_cdc -details -file ../docs/cdc_milestone4_synthesis.rpt
puts "Milestone 4 synthesis check completed."
