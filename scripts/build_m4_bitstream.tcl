# Builds the Arty A7-100T DP83848 10/100 Ethernet bitstream.
# Use the legacy project when present; otherwise create a clean M4-only project.
set project_dir ../vivado_project
set project_name arty_conv
set project_file $project_dir/$project_name.xpr
if {[file exists $project_file]} {
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
file mkdir ../docs

# Existing projects may predate Milestone 4. Add the complete source set before
# selecting the top so Vivado cannot silently fall back to an older milestone.
foreach source {
    ../rtl/top/arty_m4_ethernet_top.sv
    ../rtl/debug/reset_sync.sv
    ../rtl/debug/uart_tx.sv
    ../rtl/debug/debounce.sv
    ../rtl/debug/m4_uart_reporter.sv
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
} {
    if {[llength [get_files -quiet [file tail $source]]] == 0} {
        add_files -norecurse $source
    }
}

set_property top arty_m4_ethernet_top [current_fileset]
if {[get_property top [current_fileset]] ne "arty_m4_ethernet_top"} {
    error "Could not select arty_m4_ethernet_top; refusing to build another milestone."
}
foreach old_xdc {arty_a7_video.xdc arty_a7_camera.xdc} {
    if {[llength [get_files -quiet $old_xdc]] != 0} {
        set_property IS_ENABLED false [get_files $old_xdc]
    }
}
if {[llength [get_files -quiet arty_a7_ethernet.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse ../constraints/arty_a7_ethernet.xdc
}
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    error "Milestone 4 synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    error "Milestone 4 implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_timing_summary -file ../docs/timing_summary_milestone4.rpt
report_utilization -file ../docs/utilization_milestone4.rpt
report_cdc -details -file ../docs/cdc_milestone4.rpt
report_drc -file ../docs/drc_milestone4.rpt
set failing_paths [get_timing_paths -quiet -slack_lesser_than 0.0]
if {[llength $failing_paths] != 0} {
    error "Milestone 4 timing failed; see docs/timing_summary_milestone4.rpt"
}
set bitstream [lindex [glob $project_dir/$project_name.runs/impl_1/*.bit] 0]
set digest [exec certutil -hashfile $bitstream SHA256]
set handle [open ../docs/milestone4_bitstream_sha256.txt w]
puts $handle $digest
close $handle
puts "Milestone 4 bitstream: $bitstream"
