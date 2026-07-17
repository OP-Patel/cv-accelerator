// Reads the DP83848 identity and periodically refreshes link information.
module phy_bringup #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer POLL_MS = 250,
    parameter logic [4:0] PHY_ADDRESS = 5'd1
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        loopback_enable,
    output logic        command_start,
    output logic        command_write,
    output logic [4:0]  command_phy_address,
    output logic [4:0]  command_register_address,
    output logic [15:0] command_write_data,
    input  logic [15:0] command_read_data,
    input  logic        command_busy,
    input  logic        command_done,
    input  logic        command_ack_error,
    input  logic        command_timeout_error,
    output logic [15:0] phy_id1,
    output logic [15:0] phy_id2,
    output logic [15:0] bmsr,
    output logic [15:0] physts,
    output logic        identity_valid,
    output logic        link_up,
    output logic        speed_100,
    output logic        full_duplex,
    output logic        discovery_done,
    output logic [3:0]  error_flags
);
    localparam integer POLL_CYCLES = (CLOCK_HZ / 1000) * POLL_MS;
    localparam integer POLL_W = (POLL_CYCLES <= 1) ? 1 : $clog2(POLL_CYCLES + 1);
    typedef enum logic [3:0] {
        IDLE, ISSUE_ID1, WAIT_ID1, ISSUE_ID2, WAIT_ID2,
        ISSUE_BMSR1, WAIT_BMSR1, ISSUE_BMSR2, WAIT_BMSR2,
        ISSUE_PHYSTS, WAIT_PHYSTS, POLL_WAIT, ISSUE_BMCR, WAIT_BMCR
    } state_t;
    state_t state;
    logic [POLL_W-1:0] poll_count;
    logic saved_loopback;

    assign command_phy_address = PHY_ADDRESS;
    assign identity_valid = (phy_id1 == 16'h2000) && ((phy_id2 & 16'hFFF0) == 16'h5C90);
    assign link_up = physts[0];
    // TI PHYSTS[1] is Speed10: one means 10 Mb/s, zero means 100 Mb/s.
    assign speed_100 = !physts[1];
    assign full_duplex = physts[2];

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            command_start <= 1'b0;
            command_write <= 1'b0;
            command_register_address <= '0;
            command_write_data <= '0;
            phy_id1 <= '0;
            phy_id2 <= '0;
            bmsr <= '0;
            physts <= '0;
            discovery_done <= 1'b0;
            error_flags <= '0;
            poll_count <= '0;
            saved_loopback <= 1'b0;
        end else begin
            command_start <= 1'b0;
            if (start) begin
                state <= ISSUE_ID1;
                discovery_done <= 1'b0;
                error_flags <= '0;
                saved_loopback <= loopback_enable;
            end else case (state)
                IDLE: ;
                ISSUE_ID1: if (!command_busy) begin command_register_address <= 5'h02; command_write <= 1'b0; command_start <= 1'b1; state <= WAIT_ID1; end
                WAIT_ID1: if (command_done) begin phy_id1 <= command_read_data; error_flags[0] <= command_ack_error; error_flags[1] <= command_timeout_error; state <= ISSUE_ID2; end
                ISSUE_ID2: if (!command_busy) begin command_register_address <= 5'h03; command_write <= 1'b0; command_start <= 1'b1; state <= WAIT_ID2; end
                WAIT_ID2: if (command_done) begin phy_id2 <= command_read_data; error_flags[0] <= error_flags[0] | command_ack_error; error_flags[1] <= error_flags[1] | command_timeout_error; state <= ISSUE_BMCR; end
                ISSUE_BMCR: if (!command_busy) begin
                    command_register_address <= 5'h00;
                    command_write_data <= saved_loopback ? 16'h6100 : 16'h1200;
                    command_write <= 1'b1; command_start <= 1'b1; state <= WAIT_BMCR;
                end
                WAIT_BMCR: if (command_done) begin error_flags[0] <= error_flags[0] | command_ack_error; error_flags[1] <= error_flags[1] | command_timeout_error; state <= ISSUE_BMSR1; end
                ISSUE_BMSR1: if (!command_busy) begin command_register_address <= 5'h01; command_write <= 1'b0; command_start <= 1'b1; state <= WAIT_BMSR1; end
                WAIT_BMSR1: if (command_done) begin error_flags[0] <= error_flags[0] | command_ack_error; error_flags[1] <= error_flags[1] | command_timeout_error; state <= ISSUE_BMSR2; end
                ISSUE_BMSR2: if (!command_busy) begin command_register_address <= 5'h01; command_write <= 1'b0; command_start <= 1'b1; state <= WAIT_BMSR2; end
                WAIT_BMSR2: if (command_done) begin bmsr <= command_read_data; error_flags[0] <= error_flags[0] | command_ack_error; error_flags[1] <= error_flags[1] | command_timeout_error; state <= ISSUE_PHYSTS; end
                ISSUE_PHYSTS: if (!command_busy) begin command_register_address <= 5'h10; command_write <= 1'b0; command_start <= 1'b1; state <= WAIT_PHYSTS; end
                WAIT_PHYSTS: if (command_done) begin
                    physts <= command_read_data;
                    error_flags[0] <= error_flags[0] | command_ack_error;
                    error_flags[1] <= error_flags[1] | command_timeout_error;
                    error_flags[2] <= !((phy_id1 == 16'h2000) && ((phy_id2 & 16'hFFF0) == 16'h5C90));
                    error_flags[3] <= (command_read_data == 16'h0000) || (command_read_data == 16'hFFFF);
                    discovery_done <= 1'b1;
                    poll_count <= '0;
                    state <= POLL_WAIT;
                end
                POLL_WAIT: begin
                    if (saved_loopback != loopback_enable) begin saved_loopback <= loopback_enable; state <= ISSUE_BMCR; end
                    else if ((POLL_CYCLES <= 1) || (poll_count == POLL_CYCLES - 1)) begin poll_count <= '0; state <= ISSUE_BMSR1; end
                    else poll_count <= poll_count + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
