# Elaborates and synthesizes the Milestone 3 top without generating a bitstream.
# Camera pin placement remains gated by build_m3_bitstream.tcl.

open_project ../vivado_project/arty_conv.xpr
file mkdir ../docs
set_property top arty_m3_camera_top [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    error "Milestone 3 synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

open_run synth_1
report_utilization -file ../docs/utilization_milestone3_synthesis.rpt
puts "Milestone 3 synthesis check completed."
