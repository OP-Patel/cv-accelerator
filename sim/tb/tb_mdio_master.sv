`timescale 1ns/1ps
module tb_mdio_master;
    logic clk=0, reset=1, start=0, write_enable=0;
    logic [4:0] phy_address=1, register_address=0;
    logic [15:0] write_data=0, read_data;
    logic busy, done, ack_error, timeout_error, mdc, master_drive_low;
    logic slave_drive_low=0;
    tri1 mdio;
    assign mdio = master_drive_low ? 1'b0 : 1'bz;
    assign mdio = slave_drive_low ? 1'b0 : 1'bz;
    always #5 clk=~clk;

    mdio_master #(.CLOCK_HZ(1_000),.MDC_HZ(100),.TIMEOUT_CYCLES(10_000)) u_dut (
        .clk(clk),.reset(reset),.start(start),.write_enable(write_enable),
        .phy_address(phy_address),.register_address(register_address),.write_data(write_data),
        .read_data(read_data),.busy(busy),.done(done),.acknowledge_error(ack_error),
        .timeout_error(timeout_error),.mdc(mdc),.mdio_in(mdio),.mdio_drive_low(master_drive_low)
    );

    task automatic issue(input logic wr,input logic [4:0] regno,input logic [15:0] value);
        begin @(negedge clk); write_enable=wr; register_address=regno; write_data=value; start=1; @(negedge clk); start=0; end
    endtask
    task automatic answer_read(input logic [15:0] value);
        integer bit_number;
        begin
            wait(busy);
            for(bit_number=1;bit_number<64;bit_number=bit_number+1) begin
                @(negedge mdc);
                if(bit_number==47) slave_drive_low=1;
                else if(bit_number>=48) slave_drive_low=!value[63-bit_number];
                else slave_drive_low=0;
            end
            wait(done); #1 slave_drive_low=0;
        end
    endtask

    initial begin
        repeat(4) @(posedge clk); reset=0;
        fork answer_read(16'h2000); issue(0,5'h02,0); join
        if(read_data!=16'h2000 || ack_error || timeout_error) $fatal(1,"valid MDIO read failed: %h",read_data);
        issue(1,5'h00,16'h1200); wait(done);
        if(ack_error || timeout_error) $fatal(1,"MDIO write failed");
        issue(0,5'h03,0); wait(done);
        if(!ack_error || timeout_error) $fatal(1,"missing PHY turnaround was not detected");
        $display("PASS: tb_mdio_master"); $finish;
    end
endmodule
