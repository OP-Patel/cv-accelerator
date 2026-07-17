# Run from inside the scripts/ directory:
#   vivado -mode batch -source create_project.tcl
# or from Vivado Tcl console after `cd` into scripts/

set proj_name  "arty_conv"
set proj_dir   "../vivado_project"
set part_name  "xc7a100tcsg324-1"
set board_part "digilentinc.com:arty-a7-100:part0:1.1"

create_project $proj_name $proj_dir -part $part_name -force
set_property board_part $board_part [current_project]

# --- Board support and Milestone 1 sources ---
add_files -norecurse {
    ../rtl/top/arty_bringup_top.sv
    ../rtl/top/arty_m2_sobel_top.sv
    ../rtl/top/arty_m3_camera_top.sv
    ../rtl/top/arty_m4_ethernet_top.sv
    ../rtl/debug/reset_sync.sv
    ../rtl/debug/uart_tx.sv
    ../rtl/debug/debounce.sv
    ../rtl/debug/m2_uart_reporter.sv
    ../rtl/debug/m3_uart_reporter.sv
    ../rtl/debug/m4_uart_reporter.sv
}

# --- Milestone 4 DP83848 10/100 Ethernet MAC ---
add_files -norecurse {
    ../rtl/ethernet/ethernet_ref_clock.sv
    ../rtl/ethernet/phy_reset.sv
    ../rtl/ethernet/mdio_master.sv
    ../rtl/ethernet/phy_bringup.sv
    ../rtl/ethernet/mii_tx.sv
    ../rtl/ethernet/mii_rx.sv
    ../rtl/ethernet/ethernet_fcs.sv
    ../rtl/ethernet/ethernet_async_fifo.sv
    ../rtl/ethernet/ethernet_frame_tx.sv
    ../rtl/ethernet/ethernet_frame_rx.sv
    ../rtl/ethernet/arp_responder.sv
    ../rtl/ethernet/udp_echo.sv
}

# --- Milestone 3 OV7670 camera front end ---
add_files -norecurse {
    ../rtl/camera/camera_xclk.sv
    ../rtl/camera/sccb_master.sv
    ../rtl/camera/camera_register_init.sv
    ../rtl/camera/dvp_rgb565_capture.sv
    ../rtl/camera/camera_stream_cdc.sv
    ../rtl/camera/camera_stream_adapter.sv
    ../rtl/camera/camera_debug_counters.sv
}

# --- Milestone 2 streaming convolution sources ---
add_files -norecurse {
    ../rtl/conv/saturate_u8.sv
    ../rtl/conv/grayscale_rgb565.sv
    ../rtl/conv/line_buffer_3x3.sv
    ../rtl/conv/window_3x3.sv
    ../rtl/conv/sobel3x3.sv
    ../rtl/conv/stream_checksum.sv
    ../rtl/conv/conv_pipeline_top.sv
    ../rtl/conv/synthetic_pixel_source.sv
}

add_files -fileset sim_1 -norecurse {
    ../sim/tb/tb_uart_tx.sv
    ../sim/tb/tb_arty_m1_bringup_top.sv
    ../sim/tb/tb_saturate_u8.sv
    ../sim/tb/tb_grayscale_rgb565.sv
    ../sim/tb/tb_line_buffer_window.sv
    ../sim/tb/tb_sobel3x3.sv
    ../sim/tb/tb_conv_pipeline.sv
    ../sim/tb/tb_conv_pipeline_320.sv
    ../sim/tb/tb_arty_m2_sobel_top.sv
    ../sim/models/dvp_camera_model.sv
    ../sim/tb/tb_camera_xclk.sv
    ../sim/tb/tb_sccb_master.sv
    ../sim/tb/tb_camera_register_init.sv
    ../sim/tb/tb_dvp_rgb565_capture.sv
    ../sim/tb/tb_camera_stream_cdc.sv
    ../sim/tb/tb_camera_pipeline.sv
    ../sim/tb/tb_m3_uart_reporter.sv
    ../sim/tb/tb_mdio_master.sv
    ../sim/tb/tb_mii_tx_rx.sv
    ../sim/tb/tb_ethernet_frames.sv
    ../sim/tb/tb_arp_udp.sv
    ../sim/models/dp83848_mii_model.sv
    ../sim/tb/tb_arty_m4_ethernet_top.sv
}

add_files -fileset constrs_1 -norecurse {
    ../constraints/arty_a7_video.xdc
}

set_property top arty_m2_sobel_top [current_fileset]
set_property top tb_uart_tx [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created at $proj_dir"
