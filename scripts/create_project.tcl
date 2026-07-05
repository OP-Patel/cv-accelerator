# Run from inside the scripts/ directory:
#   vivado -mode batch -source create_project.tcl
# or from Vivado Tcl console after `cd` into scripts/

set proj_name  "arty_conv"
set proj_dir   "../vivado_project"
set part_name  "xc7a100tcsg324-1"
set board_part "digilentinc.com:arty-a7-100:part0:1.1"

create_project $proj_name $proj_dir -part $part_name -force
set_property board_part $board_part [current_project]

# --- Milestone 1 sources ---
add_files -norecurse {
    ../rtl/top/arty_bringup_top.sv
    ../rtl/debug/uart_tx.sv
    ../rtl/debug/debounce.sv
}

add_files -fileset sim_1 -norecurse {
    ../sim/tb/tb_uart_tx.sv
}

add_files -fileset constrs_1 -norecurse {
    ../constraints/arty_a7_video.xdc
}

set_property top arty_bringup_top [current_fileset]
set_property top tb_uart_tx [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created at $proj_dir"