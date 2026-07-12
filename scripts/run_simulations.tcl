# Run from inside scripts/ after create_project.tcl:
#   vivado -mode batch -source run_simulations.tcl

open_project ../vivado_project/arty_conv.xpr

foreach testbench {
    tb_uart_tx
    tb_arty_m1_bringup_top
    tb_saturate_u8
    tb_grayscale_rgb565
    tb_line_buffer_window
    tb_sobel3x3
    tb_conv_pipeline
    tb_conv_pipeline_320
    tb_arty_m2_sobel_top
} {
    set_property top $testbench [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
    puts "Completed behavioral simulation: $testbench"
}
