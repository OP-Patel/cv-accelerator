# Elaborates/synthesizes the 10/100 Ethernet top without generating a bitstream.
if {[file exists ../vivado_project/arty_conv.xpr]} {
    open_project ../vivado_project/arty_conv.xpr
} else {
    open_project ../vivado_project_m4/arty_conv_m4.xpr
}
file mkdir ../docs
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
    error "Could not select arty_m4_ethernet_top."
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
open_run synth_1
report_utilization -file ../docs/utilization_milestone4_synthesis.rpt
report_cdc -details -file ../docs/cdc_milestone4_synthesis.rpt
puts "Milestone 4 synthesis check completed."
