# Run from scripts/: vivado -mode batch -source run_m4_simulations.tcl
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
foreach source $m4_design_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -norecurse $source
    }
}
foreach test_source $m4_sim_sources {
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
