# Run from scripts/: vivado -mode batch -source run_m4_simulations.tcl
if {[file exists ../vivado_project/arty_conv.xpr]} {
    open_project ../vivado_project/arty_conv.xpr
} else {
    open_project ../vivado_project_m4/arty_conv_m4.xpr
}
foreach test_source {
    ../sim/models/dp83848_mii_model.sv
    ../sim/tb/tb_mdio_master.sv
    ../sim/tb/tb_mii_tx_rx.sv
    ../sim/tb/tb_ethernet_frames.sv
    ../sim/tb/tb_arp_udp.sv
    ../sim/tb/tb_arty_m4_ethernet_top.sv
} {
    if {[llength [get_files -quiet [file tail $test_source]]] == 0} {
        add_files -fileset sim_1 -norecurse $test_source
    }
}
foreach testbench {tb_mdio_master tb_mii_tx_rx tb_ethernet_frames tb_arp_udp tb_arty_m4_ethernet_top} {
    set_property top $testbench [get_filesets sim_1]
    update_compile_order -fileset sim_1
    reset_simulation -simset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    set log_path [get_property DIRECTORY [current_project]]/[get_property NAME [current_project]].sim/sim_1/behav/xsim/simulate.log
    set handle [open $log_path r]
    set text [read $handle]
    close $handle
    if {[string first "PASS: $testbench" $text] < 0} {
        error "Simulation did not report PASS: $testbench"
    }
    close_sim
    puts "Completed Milestone 4 simulation: $testbench"
}
