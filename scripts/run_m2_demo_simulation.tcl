# Run only the complete synthetic-source, Sobel, checksum, and UART board-demo test.

open_project ../vivado_project/arty_conv.xpr
set_property top tb_arty_m2_sobel_top [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
puts "Completed behavioral simulation: tb_arty_m2_sobel_top"
