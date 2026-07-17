// IEEE 802.3 Clause 22 MDIO master. MDIO is open-drain at the top level.
module mdio_master #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer MDC_HZ = 2_500_000,
    parameter integer TIMEOUT_CYCLES = 100_000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        write_enable,
    input  logic [4:0]  phy_address,
    input  logic [4:0]  register_address,
    input  logic [15:0] write_data,
    output logic [15:0] read_data,
    output logic        busy,
    output logic        done,
    output logic        acknowledge_error,
    output logic        timeout_error,
    output logic        mdc,
    input  logic        mdio_in,
    output logic        mdio_drive_low
);
    localparam integer HALF_DIV = (CLOCK_HZ / (MDC_HZ * 2));
    localparam integer DIV_W = (HALF_DIV <= 1) ? 1 : $clog2(HALF_DIV);
    localparam integer TIMEOUT_W = (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES + 1);
    logic [DIV_W-1:0] divider;
    logic [TIMEOUT_W-1:0] timeout_count;
    logic [5:0] bit_index;
    logic saved_write;
    logic [4:0] saved_phy, saved_register;
    logic [15:0] saved_write_data;

    function automatic logic output_bit(
        input logic [5:0] index,
        input logic is_write,
        input logic [4:0] phy,
        input logic [4:0] reg_addr,
        input logic [15:0] data_value
    );
        begin
            if (index < 32) output_bit = 1'b1;
            else if (index == 32) output_bit = 1'b0;
            else if (index == 33) output_bit = 1'b1;
            else if (index == 34) output_bit = is_write ? 1'b0 : 1'b1;
            else if (index == 35) output_bit = is_write ? 1'b1 : 1'b0;
            else if (index < 41) output_bit = phy[40-index];
            else if (index < 46) output_bit = reg_addr[45-index];
            else if (index == 46) output_bit = 1'b1;
            else if (index == 47) output_bit = 1'b0;
            else output_bit = data_value[63-index];
        end
    endfunction

    function automatic logic should_drive(
        input logic [5:0] index,
        input logic is_write
    );
        begin
            // Ones are released because MDIO is open-drain. During reads the
            // complete turnaround and data fields belong to the PHY.
            should_drive = is_write || (index < 46);
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            read_data <= '0;
            busy <= 1'b0;
            done <= 1'b0;
            acknowledge_error <= 1'b0;
            timeout_error <= 1'b0;
            mdc <= 1'b0;
            mdio_drive_low <= 1'b0;
            divider <= '0;
            timeout_count <= '0;
            bit_index <= '0;
            saved_write <= 1'b0;
            saved_phy <= '0;
            saved_register <= '0;
            saved_write_data <= '0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                mdc <= 1'b0;
                mdio_drive_low <= 1'b0;
                divider <= '0;
                timeout_count <= '0;
                if (start) begin
                    busy <= 1'b1;
                    acknowledge_error <= 1'b0;
                    timeout_error <= 1'b0;
                    read_data <= '0;
                    bit_index <= '0;
                    saved_write <= write_enable;
                    saved_phy <= phy_address;
                    saved_register <= register_address;
                    saved_write_data <= write_data;
                    mdio_drive_low <= !output_bit(0, write_enable, phy_address, register_address, write_data);
                end
            end else if (timeout_count == TIMEOUT_CYCLES - 1) begin
                busy <= 1'b0;
                done <= 1'b1;
                timeout_error <= 1'b1;
                mdc <= 1'b0;
                mdio_drive_low <= 1'b0;
            end else begin
                timeout_count <= timeout_count + 1'b1;
                if ((HALF_DIV <= 1) || (divider == HALF_DIV - 1)) begin
                    divider <= '0;
                    if (!mdc) begin
                        // Rising MDC samples PHY-owned read bits.
                        mdc <= 1'b1;
                        if (!saved_write && bit_index == 47 && mdio_in) acknowledge_error <= 1'b1;
                        if (!saved_write && bit_index >= 48) read_data[63-bit_index] <= mdio_in;
                        if (bit_index == 63) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            mdio_drive_low <= 1'b0;
                        end
                    end else begin
                        // Change MDIO only while MDC is low.
                        mdc <= 1'b0;
                        bit_index <= bit_index + 1'b1;
                        if (should_drive(bit_index + 1'b1, saved_write)) begin
                            mdio_drive_low <= !output_bit(
                                bit_index + 1'b1, saved_write, saved_phy,
                                saved_register, saved_write_data
                            );
                        end else mdio_drive_low <= 1'b0;
                    end
                end else divider <= divider + 1'b1;
            end
        end
    end
endmodule
