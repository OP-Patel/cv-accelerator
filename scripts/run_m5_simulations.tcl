# Runs the self-checking Milestone 5 protocol and integrated datapath tests.
source m5_project_files.tcl
set project_dir ../vivado_project_m5
set project_file $project_dir/arty_conv_m5.xpr
if {[file exists $project_file]} {
    open_project $project_file
} else {
    create_project arty_conv_m5 $project_dir -part xc7a100tcsg324-1
    set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]
}
foreach source $m5_design_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -norecurse $source
    }
}
foreach source $m5_sim_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -fileset sim_1 -norecurse $source
    }
}
foreach testbench {
    tb_m5_control_receiver
    tb_m5_tx_scheduler
    tb_m5_stream_packetizer
    tb_m5_camera_udp
} {
    set_property top $testbench [get_filesets sim_1]
    update_compile_order -fileset sim_1
    reset_simulation -simset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    set log_path [get_property DIRECTORY [current_project]]/[get_property NAME [current_project]].sim/sim_1/behav/xsim/simulate.log
    set handle [open $log_path r]
    set log_text [read $handle]
    close $handle
    if {[string first "PASS: $testbench" $log_text] < 0} {
        error "Simulation did not report PASS: $testbench"
    }
    close_sim
    puts "Completed Milestone 5 simulation: $testbench"
}
