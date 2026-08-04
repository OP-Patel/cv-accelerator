# Shared Milestone 4 source inventory for simulation, synthesis, and builds.
set m4_design_sources {
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
    ../rtl/ethernet/ethernet_async_fifo.sv
    ../rtl/ethernet/ethernet_frame_tx.sv
    ../rtl/ethernet/ethernet_frame_rx.sv
    ../rtl/ethernet/arp_responder.sv
    ../rtl/ethernet/udp_echo.sv
}

set m4_sim_sources {
    ../rtl/ethernet/ethernet_fcs.sv
    ../sim/models/dp83848_mii_model.sv
    ../sim/tb/tb_mdio_master.sv
    ../sim/tb/tb_mii_tx_rx.sv
    ../sim/tb/tb_ethernet_frames.sv
    ../sim/tb/tb_arp_udp.sv
    ../sim/tb/tb_arty_m4_ethernet_top.sv
}
