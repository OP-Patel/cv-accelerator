# Runs one named behavioral testbench, for example:
#   vivado -mode batch -source run_single_simulation.tcl -tclargs tb_camera_pipeline

if {[llength $argv] != 1} {
    error "Expected exactly one testbench name"
}

set testbench [lindex $argv 0]
open_project ../vivado_project/arty_conv.xpr
set_property top $testbench [get_filesets sim_1]
update_compile_order -fileset sim_1
reset_simulation -simset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
puts "Completed behavioral simulation: $testbench"
