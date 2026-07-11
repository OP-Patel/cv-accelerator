# Run from inside scripts/ after create_project.tcl:
#   vivado -mode batch -source run_simulations.tcl

open_project ../vivado_project/arty_conv.xpr

foreach testbench {tb_uart_tx tb_arty_m1_bringup_top} {
    set_property top $testbench [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
    puts "Completed behavioral simulation: $testbench"
}
