# Run from scripts/ after create_project.tcl:
#   vivado -mode batch -source run_m3_simulations.tcl

open_project ../vivado_project/arty_conv.xpr

foreach testbench {
    tb_camera_xclk
    tb_sccb_master
    tb_camera_register_init
    tb_dvp_rgb565_capture
    tb_camera_stream_cdc
    tb_camera_pipeline
    tb_camera_pipeline_320
    tb_m3_uart_reporter
} {
    set_property top $testbench [get_filesets sim_1]
    update_compile_order -fileset sim_1
    reset_simulation -simset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all

    set log_path "../vivado_project/arty_conv.sim/sim_1/behav/xsim/simulate.log"
    set log_file [open $log_path r]
    set log_text [read $log_file]
    close $log_file
    if {[string first "PASS: $testbench" $log_text] < 0} {
        error "Simulation did not report PASS: $testbench"
    }

    close_sim
    puts "Completed Milestone 3 behavioral simulation: $testbench"
}
