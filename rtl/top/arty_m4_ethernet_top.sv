// Arty A7-100T DP83848 10/100 MII bring-up, raw test, ARP, and UDP echo top.
module arty_m4_ethernet_top #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer UART_BAUD = 115_200,
    parameter integer DEBOUNCE_CYCLES = 1_000_000,
    parameter integer PHY_RESET_US = 10_000,
    parameter integer PHY_STARTUP_US = 10_000,
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter logic [31:0] FPGA_IP = 32'hC0A8_0A02,
    parameter logic [15:0] UDP_PORT = 16'd4000
) (
    input  logic       clk_100mhz,
    input  logic       reset_btn,
    input  logic [2:0] btn,
    input  logic [3:0] sw,
    input  logic       uart_rx,
    output logic       uart_tx,
    output logic [3:0] led,
    input  logic       eth_col,
    input  logic       eth_crs,
    output logic       eth_mdc,
    inout  wire        eth_mdio,
    output logic       eth_ref_clk,
    output logic       eth_rstn,
    input  logic       eth_rx_clk,
    input  logic       eth_rx_dv,
    input  logic [3:0] eth_rxd,
    input  logic       eth_rxerr,
    input  logic       eth_tx_clk,
    output logic       eth_tx_en,
    output logic [3:0] eth_txd
);
    typedef enum logic [1:0] {SOURCE_TEST, SOURCE_ARP, SOURCE_UDP} source_t;
    logic reset, ref_ready, phy_ready;
    logic [26:0] heartbeat;
    logic [2:0] btn_clean, btn_delayed;
    logic [3:0] sw_clean;
    logic restart_pulse, clear_level, clear_pulse, transmit_pulse;
    logic test_toggle;

    logic mdio_start, mdio_write, mdio_busy, mdio_done, mdio_ack_error, mdio_timeout;
    logic [4:0] mdio_phy, mdio_register;
    logic [15:0] mdio_write_data, mdio_read_data;
    logic mdio_drive_low;
    logic bringup_start, phy_ready_delayed, discovery_delayed, link_delayed;
    logic [15:0] phy_id1, phy_id2, bmsr, physts;
    logic identity_valid, link_up, speed_100, full_duplex, discovery_done;
    logic [3:0] phy_errors;

    (* ASYNC_REG = "TRUE" *) logic [1:0] rx_reset_sync, tx_reset_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] clear_rx_sync, test_toggle_sync, continuous_sync;
    logic rx_reset, tx_reset, seen_test_toggle;
    logic [7:0] rx_byte;
    logic rx_byte_valid, rx_frame_start, rx_frame_end, rx_error, rx_odd;
    logic [10:0] rx_read_address;
    logic [7:0] rx_read_data;
    logic rx_frame_done, rx_frame_valid, rx_ipv4_checksum_valid;
    logic [10:0] rx_frame_length;
    logic [47:0] rx_destination_mac, rx_source_mac;
    logic [15:0] rx_ether_type, rx_arp_opcode, rx_udp_source_port, rx_udp_destination_port, rx_udp_length;
    logic [15:0] rx_ip_total_length;
    logic [31:0] rx_source_ip, rx_destination_ip;
    logic [7:0] rx_ip_protocol;
    logic [31:0] good_frames, bad_fcs_frames, runt_frames, oversize_frames, rx_error_frames;
    logic [31:0] protocol_error_frames, sequence_gap_frames;

    logic frame_tx_start, frame_tx_busy, frame_tx_done, frame_tx_length_error;
    logic [10:0] frame_tx_length, frame_tx_index;
    logic [7:0] frame_tx_data, encoded_data;
    logic encoded_valid, encoded_last;
    logic fifo_full, fifo_empty, fifo_overflow, fifo_underflow, fifo_read, mii_byte_ready;
    logic [8:0] fifo_output;
    logic mii_underrun;
    source_t active_source;
    logic [47:0] saved_source_mac;
    logic [31:0] saved_source_ip;
    logic [15:0] saved_source_port, saved_udp_length;
    logic [31:0] tx_frames;
    logic [31:0] dropped_frames;

    logic [10:0] arp_length, udp_reply_length, udp_read_address;
    logic [7:0] arp_data, udp_data;
    logic [31:0] test_sequence;
    logic [31:0] test_payload_crc;
    logic [21:0] continuous_count;

    logic report_pending, report_start, reporter_busy, uart_send, uart_busy;
    logic [7:0] uart_data;
    logic [15:0] combined_errors;
    logic [31:0] bad_count, bad_count_rx, drop_count;
    logic [31:0] report_tx_count, report_rx_count, report_bad_count;
    logic [31:0] report_dropped_count, report_sequence_gap_count;
    logic report_frame_length_error, report_fifo_overflow;
    logic report_fifo_underflow, report_mii_underrun;
    (* ASYNC_REG = "TRUE" *) logic [161:0] rx_status_meta, rx_status_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] tx_status_meta, tx_status_sync;

    reset_sync u_reset (.clk(clk_100mhz), .async_reset_in(reset_btn), .sync_reset_out(reset));
    ethernet_ref_clock u_ref_clock (
        .clk_100mhz(clk_100mhz), .reset(reset),
        .eth_ref_clk(eth_ref_clk), .clock_ready(ref_ready)
    );

    genvar i;
    generate
        for (i=0; i<3; i=i+1) begin : g_buttons
            debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_button (
                .clk(clk_100mhz), .reset(reset), .noisy_in(btn[i]), .clean_out(btn_clean[i])
            );
        end
        for (i=0; i<4; i=i+1) begin : g_switches
            debounce #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_switch (
                .clk(clk_100mhz), .reset(reset), .noisy_in(sw[i]), .clean_out(sw_clean[i])
            );
        end
    endgenerate
    assign restart_pulse = btn_clean[0] && !btn_delayed[0];
    assign clear_level = btn_clean[1];
    assign clear_pulse = btn_clean[1] && !btn_delayed[1];
    assign transmit_pulse = btn_clean[2] && !btn_delayed[2];

    phy_reset #(
        .CLOCK_HZ(CLOCK_HZ), .RESET_US(PHY_RESET_US), .STARTUP_US(PHY_STARTUP_US)
    ) u_phy_reset (
        .clk(clk_100mhz), .reset(reset), .restart(restart_pulse),
        .ref_clock_ready(ref_ready), .eth_rstn(eth_rstn), .ready(phy_ready)
    );
    mdio_master #(.CLOCK_HZ(CLOCK_HZ)) u_mdio (
        .clk(clk_100mhz), .reset(reset), .start(mdio_start), .write_enable(mdio_write),
        .phy_address(mdio_phy), .register_address(mdio_register), .write_data(mdio_write_data),
        .read_data(mdio_read_data), .busy(mdio_busy), .done(mdio_done),
        .acknowledge_error(mdio_ack_error), .timeout_error(mdio_timeout),
        .mdc(eth_mdc), .mdio_in(eth_mdio), .mdio_drive_low(mdio_drive_low)
    );
    assign eth_mdio = mdio_drive_low ? 1'b0 : 1'bz;
    assign bringup_start = phy_ready && !phy_ready_delayed;
    phy_bringup #(.CLOCK_HZ(CLOCK_HZ)) u_bringup (
        .clk(clk_100mhz), .reset(reset), .start(bringup_start),
        .loopback_enable(sw_clean[1]), .command_start(mdio_start),
        .command_write(mdio_write), .command_phy_address(mdio_phy),
        .command_register_address(mdio_register), .command_write_data(mdio_write_data),
        .command_read_data(mdio_read_data), .command_busy(mdio_busy), .command_done(mdio_done),
        .command_ack_error(mdio_ack_error), .command_timeout_error(mdio_timeout),
        .phy_id1(phy_id1), .phy_id2(phy_id2), .bmsr(bmsr), .physts(physts),
        .identity_valid(identity_valid), .link_up(link_up), .speed_100(speed_100),
        .full_duplex(full_duplex), .discovery_done(discovery_done), .error_flags(phy_errors)
    );

    always_ff @(posedge eth_rx_clk or posedge reset_btn) begin
        if (reset_btn) begin rx_reset_sync <= 2'b11; clear_rx_sync <= '0; test_toggle_sync <= '0; continuous_sync <= '0; end
        else begin
            rx_reset_sync <= {rx_reset_sync[0], reset || !phy_ready};
            clear_rx_sync <= {clear_rx_sync[0], clear_level};
            test_toggle_sync <= {test_toggle_sync[0], test_toggle};
            continuous_sync <= {continuous_sync[0], sw_clean[0]};
        end
    end
    always_ff @(posedge eth_tx_clk or posedge reset_btn) begin
        if (reset_btn) tx_reset_sync <= 2'b11;
        else tx_reset_sync <= {tx_reset_sync[0], reset || !phy_ready};
    end
    assign rx_reset = rx_reset_sync[1];
    assign tx_reset = tx_reset_sync[1];

    mii_rx u_mii_rx (
        .rx_clk(eth_rx_clk), .reset(rx_reset), .eth_rxd(eth_rxd), .eth_rx_dv(eth_rx_dv),
        .eth_rxerr(eth_rxerr), .byte_data(rx_byte), .byte_valid(rx_byte_valid),
        .frame_start(rx_frame_start), .frame_end(rx_frame_end), .rx_error(rx_error), .odd_nibble(rx_odd)
    );
    ethernet_frame_rx u_frame_rx (
        .clk(eth_rx_clk), .reset(rx_reset), .clear_errors(clear_rx_sync[1]),
        .byte_data(rx_byte), .byte_valid(rx_byte_valid), .frame_start(rx_frame_start),
        .frame_end(rx_frame_end), .mii_rx_error(rx_error), .odd_nibble(rx_odd),
        .read_address(rx_read_address), .read_data(rx_read_data), .frame_done(rx_frame_done),
        .frame_valid(rx_frame_valid), .frame_length(rx_frame_length),
        .destination_mac(rx_destination_mac), .source_mac(rx_source_mac), .ether_type(rx_ether_type),
        .source_ip(rx_source_ip), .destination_ip(rx_destination_ip), .arp_opcode(rx_arp_opcode),
        .udp_source_port(rx_udp_source_port), .udp_destination_port(rx_udp_destination_port),
        .udp_length(rx_udp_length), .ip_protocol(rx_ip_protocol),
        .ip_total_length(rx_ip_total_length),
        .ipv4_checksum_valid(rx_ipv4_checksum_valid), .good_frames(good_frames),
        .bad_fcs_frames(bad_fcs_frames), .runt_frames(runt_frames),
        .oversize_frames(oversize_frames), .rx_error_frames(rx_error_frames),
        .protocol_error_frames(protocol_error_frames), .sequence_gap_frames(sequence_gap_frames)
    );

    arp_responder #(.FPGA_MAC(FPGA_MAC), .FPGA_IP(FPGA_IP)) u_arp (
        .request_source_mac(saved_source_mac), .request_source_ip(saved_source_ip),
        .reply_index(frame_tx_index), .reply_length(arp_length), .reply_data(arp_data)
    );
    udp_echo #(.FPGA_MAC(FPGA_MAC), .FPGA_IP(FPGA_IP), .UDP_PORT(UDP_PORT)) u_udp (
        .request_source_mac(saved_source_mac), .request_source_ip(saved_source_ip),
        .request_source_port(saved_source_port), .request_udp_length(saved_udp_length),
        .reply_index(frame_tx_index), .request_read_address(udp_read_address),
        .request_read_data(rx_read_data), .reply_length(udp_reply_length), .reply_data(udp_data)
    );
    assign rx_read_address = (active_source == SOURCE_UDP) ? udp_read_address : 11'd0;

    function automatic logic [31:0] test_crc(input logic [31:0] seq_value);
        logic [31:0] c; logic [7:0] b; integer n, k;
        begin
            c = 32'hFFFF_FFFF;
            for (n=0; n<42; n=n+1) begin
                if (n<6) case(n) 0:b="M";1:b="4";2:b="T";3:b="E";4:b="S";default:b="T"; endcase
                else if (n<10) b = seq_value[31-((n-6)*8) -: 8];
                else if (n==10) b=8'h00; else if (n==11) b=8'd30;
                else b=(n-12) ^ seq_value[7:0];
                for (k=0;k<8;k=k+1) c=(c>>1)^((c[0]^b[k])?32'hEDB88320:32'h0);
            end
            test_crc = ~c;
        end
    endfunction
    always_comb begin
        test_payload_crc = test_crc(test_sequence);
        if (frame_tx_index < 6) frame_tx_data = 8'hFF;
        else if (frame_tx_index < 12) frame_tx_data = FPGA_MAC[47-((frame_tx_index-6)*8) -: 8];
        else if (frame_tx_index==12) frame_tx_data=8'h88;
        else if (frame_tx_index==13) frame_tx_data=8'hB5;
        else if (frame_tx_index<20) case(frame_tx_index) 14:frame_tx_data="M";15:frame_tx_data="4";16:frame_tx_data="T";17:frame_tx_data="E";18:frame_tx_data="S";default:frame_tx_data="T"; endcase
        else if (frame_tx_index<24) frame_tx_data=test_sequence[31-((frame_tx_index-20)*8) -: 8];
        else if (frame_tx_index==24) frame_tx_data=8'h00;
        else if (frame_tx_index==25) frame_tx_data=8'd30;
        else if (frame_tx_index<56) frame_tx_data=(frame_tx_index-26)^test_sequence[7:0];
        else frame_tx_data=test_payload_crc[((frame_tx_index-56)*8) +: 8];
        if (active_source==SOURCE_ARP) frame_tx_data=arp_data;
        else if (active_source==SOURCE_UDP) frame_tx_data=udp_data;
        frame_tx_length = (active_source==SOURCE_ARP) ? arp_length :
                          (active_source==SOURCE_UDP) ? udp_reply_length : 11'd60;
    end

    ethernet_frame_tx u_frame_tx (
        .clk(eth_rx_clk), .reset(rx_reset), .start(frame_tx_start),
        .frame_length(frame_tx_length), .frame_data_index(frame_tx_index), .frame_data(frame_tx_data),
        .output_data(encoded_data), .output_valid(encoded_valid), .output_last(encoded_last),
        .output_ready(!fifo_full), .busy(frame_tx_busy), .done(frame_tx_done),
        .length_error(frame_tx_length_error)
    );
    ethernet_async_fifo u_tx_fifo (
        .write_reset(rx_reset), .write_clk(eth_rx_clk), .write_enable(encoded_valid && !fifo_full),
        .write_data({encoded_last,encoded_data}), .full(fifo_full), .overflow(fifo_overflow),
        .read_clk(eth_tx_clk), .read_reset(tx_reset), .read_enable(fifo_read), .read_data(fifo_output),
        .empty(fifo_empty), .underflow(fifo_underflow)
    );
    assign fifo_read = !fifo_empty && mii_byte_ready;
    mii_tx u_mii_tx (
        .tx_clk(eth_tx_clk), .reset(tx_reset), .byte_data(fifo_output[7:0]),
        .byte_valid(!fifo_empty), .byte_last(fifo_output[8]), .byte_ready(mii_byte_ready),
        .eth_txd(eth_txd), .eth_tx_en(eth_tx_en), .underrun(mii_underrun)
    );

    always_ff @(posedge eth_rx_clk or posedge rx_reset) begin
        if (rx_reset) begin
            frame_tx_start<=1'b0; active_source<=SOURCE_TEST; saved_source_mac<='0;
            saved_source_ip<='0; saved_source_port<='0; saved_udp_length<='0;
            seen_test_toggle<=1'b0; test_sequence<='0; tx_frames<='0;
            dropped_frames<='0; continuous_count<='0;
            bad_count_rx<='0;
        end else begin
            bad_count_rx<=bad_count;
            frame_tx_start<=1'b0;
            if (clear_rx_sync[1]) begin tx_frames<='0; dropped_frames<='0; end
            if (frame_tx_done) tx_frames<=tx_frames+1'b1;
            continuous_count<=continuous_count+1'b1;
            if (!frame_tx_busy) begin
                if (rx_frame_done && rx_frame_valid && rx_ether_type==16'h0806 &&
                    rx_arp_opcode==16'h0001 && rx_destination_ip==FPGA_IP) begin
                    active_source<=SOURCE_ARP; saved_source_mac<=rx_source_mac;
                    saved_source_ip<=rx_source_ip; frame_tx_start<=1'b1;
                end else if (rx_frame_done && rx_frame_valid && rx_ether_type==16'h0800 &&
                    rx_ip_protocol==8'h11 && rx_ipv4_checksum_valid && rx_destination_ip==FPGA_IP &&
                    rx_udp_destination_port==UDP_PORT && rx_udp_length>=8 && rx_udp_length<=1480 &&
                    rx_ip_total_length==(16'd20+rx_udp_length) && rx_frame_length>=(11'd34+rx_udp_length)) begin
                    active_source<=SOURCE_UDP; saved_source_mac<=rx_source_mac;
                    saved_source_ip<=rx_source_ip; saved_source_port<=rx_udp_source_port;
                    saved_udp_length<=rx_udp_length; frame_tx_start<=1'b1;
                end else if ((test_toggle_sync[1]!=seen_test_toggle) || (continuous_sync[1] && continuous_count==0)) begin
                    seen_test_toggle<=test_toggle_sync[1]; active_source<=SOURCE_TEST;
                    test_sequence<=test_sequence+1'b1; frame_tx_start<=1'b1;
                end
            end else if (rx_frame_done && rx_frame_valid) dropped_frames<=dropped_frames+1'b1;
        end
    end

    assign bad_count = bad_fcs_frames+runt_frames+oversize_frames+rx_error_frames+protocol_error_frames;
    assign {report_frame_length_error, report_fifo_overflow, report_dropped_count,
            report_sequence_gap_count, report_bad_count, report_rx_count,
            report_tx_count} = rx_status_sync;
    assign {report_fifo_underflow, report_mii_underrun} = tx_status_sync;
    assign drop_count = report_dropped_count+report_sequence_gap_count+
                        report_fifo_overflow+report_fifo_underflow+report_mii_underrun;
    always_comb begin
        combined_errors='0; combined_errors[3:0]=phy_errors;
        combined_errors[4]=report_frame_length_error; combined_errors[5]=report_fifo_overflow;
        combined_errors[6]=report_fifo_underflow; combined_errors[7]=report_mii_underrun;
        combined_errors[8]=(report_bad_count!=0); combined_errors[9]=(report_dropped_count!=0);
        combined_errors[10]=eth_col; combined_errors[11]=1'b0;
    end
    uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD_RATE(UART_BAUD)) u_uart (
        .clk(clk_100mhz),.reset(reset),.data(uart_data),.send(uart_send),.tx(uart_tx),.busy(uart_busy)
    );
    m4_uart_reporter u_reporter (
        .clk(clk_100mhz),.reset(reset),.start(report_start),
        .phy_pass(identity_valid && discovery_done && !(|phy_errors)),
        .packet_pass(combined_errors[11:4]==0),.phy_id1(phy_id1),.phy_id2(phy_id2),
        .link_up(link_up),.speed_100(speed_100),.full_duplex(full_duplex),
        .tx_count(report_tx_count),.rx_count(report_rx_count),.bad_count(report_bad_count),
        .drop_count(drop_count),.error_flags(combined_errors),
        .uart_data(uart_data),.uart_send(uart_send),.uart_busy(uart_busy),.busy(reporter_busy)
    );

    always_ff @(posedge clk_100mhz) begin
        if (reset) begin
            heartbeat<='0; btn_delayed<='0; phy_ready_delayed<=1'b0;
            discovery_delayed<=1'b0; link_delayed<=1'b0;
            test_toggle<=1'b0; report_pending<=1'b0; report_start<=1'b0;
            rx_status_meta<='0; rx_status_sync<='0;
            tx_status_meta<='0; tx_status_sync<='0;
        end else begin
            rx_status_meta<={frame_tx_length_error, fifo_overflow, dropped_frames,
                             sequence_gap_frames, bad_count_rx, good_frames, tx_frames};
            rx_status_sync<=rx_status_meta;
            tx_status_meta<={fifo_underflow, mii_underrun};
            tx_status_sync<=tx_status_meta;
            heartbeat<=heartbeat+1'b1; btn_delayed<=btn_clean;
            phy_ready_delayed<=phy_ready; discovery_delayed<=discovery_done;
            link_delayed<=link_up; report_start<=1'b0;
            if (transmit_pulse) test_toggle<=~test_toggle;
            if (transmit_pulse || restart_pulse || clear_pulse ||
                (discovery_done && !discovery_delayed) || (link_up != link_delayed)) report_pending<=1'b1;
            else if (report_pending && !reporter_busy) begin report_pending<=1'b0; report_start<=1'b1; end
        end
    end
    assign led = reset ? 4'b0 : {|combined_errors, (report_tx_count!=0)||(report_rx_count!=0), identity_valid&&link_up, heartbeat[26]};
    logic unused;
    assign unused = uart_rx ^ bmsr[0] ^ physts[15] ^ rx_destination_mac[0] ^
                    rx_frame_length[0] ^ eth_crs;
endmodule
