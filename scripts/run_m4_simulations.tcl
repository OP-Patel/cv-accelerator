# Run from scripts/: vivado -mode batch -source run_m4_simulations.tcl
open_project ../vivado_project/arty_conv.xpr
foreach testbench {tb_mdio_master tb_mii_tx_rx tb_ethernet_frames tb_arp_udp tb_arty_m4_ethernet_top} {
    set_property top $testbench [get_filesets sim_1]
    update_compile_order -fileset sim_1
    reset_simulation -simset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    set log_path "../vivado_project/arty_conv.sim/sim_1/behav/xsim/simulate.log"
    set handle [open $log_path r]
    set text [read $handle]
    close $handle
    if {[string first "PASS: $testbench" $text] < 0} {
        error "Simulation did not report PASS: $testbench"
    }
    close_sim
    puts "Completed Milestone 4 simulation: $testbench"
}
