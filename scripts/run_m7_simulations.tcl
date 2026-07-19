# Runs preserved M5 regressions and all board-independent M7 RTL tests.
source m7_project_files.tcl
set project_dir ../vivado_project_m7
set project_file $project_dir/arty_conv_m7.xpr
if {[file exists $project_file]} {
    open_project $project_file
} else {
    create_project arty_conv_m7 $project_dir -part xc7a100tcsg324-1
    set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]
}
foreach source $m7_design_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -norecurse $source
    }
}
foreach source $m7_sim_sources {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -fileset sim_1 -norecurse $source
    }
}
set m7_testbenches {
    tb_m5_control_receiver
    tb_m5_tx_scheduler
    tb_m5_stream_packetizer
    tb_m5_camera_udp
    tb_camera_register_profiles
    tb_camera_timing_monitor
    tb_m7_threshold_sobel
    tb_m7_core_metrics
    tb_m7_accelerated_core
    tb_m7_control_receiver
    tb_conv_pipeline_320
}
if {[info exists ::env(M7_TESTBENCHES)] && $::env(M7_TESTBENCHES) ne ""} {
    set m7_testbenches [split $::env(M7_TESTBENCHES) ","]
}
foreach testbench $m7_testbenches {
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
    puts "Completed Milestone 7 simulation: $testbench"
}
