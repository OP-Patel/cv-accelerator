# Shared Milestone 7 source inventory for simulation, synthesis, and implementation.
source m5_project_files.tcl
set m7_design_sources [concat $m5_design_sources {
    ../rtl/top/arty_m7_camera_ethernet_top.sv
    ../rtl/conv/synthetic_pixel_source.sv
}]
set m7_sim_sources [concat $m5_sim_sources {
    ../sim/tb/tb_camera_register_profiles.sv
    ../sim/tb/tb_camera_timing_monitor.sv
    ../sim/tb/tb_m7_threshold_sobel.sv
    ../sim/tb/tb_m7_core_metrics.sv
    ../sim/tb/tb_m7_accelerated_core.sv
    ../sim/tb/tb_m7_control_receiver.sv
    ../sim/tb/tb_conv_pipeline_320.sv
}]
