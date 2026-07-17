`timescale 1ns/1ps
// Focused simulation model: Clause 22 registers plus 100-Mb/s MII loopback.
module dp83848_mii_model (
    input  logic       ref_clk,
    input  logic       reset_n,
    input  logic       mdc,
    inout  tri         mdio,
    input  logic [3:0] txd,
    input  logic       tx_en,
    output logic       tx_clk,
    output logic       rx_clk,
    output logic [3:0] rxd,
    output logic       rx_dv,
    output logic       rxerr,
    output logic       col,
    output logic       crs
);
    logic mdio_drive_low;
    logic [15:0] registers[0:31];
    logic [4:0] phy_address, register_address;
    logic [1:0] opcode;
    logic [15:0] write_shift, read_value;
    integer one_count, bit_number;
    logic transaction;
    assign mdio = mdio_drive_low ? 1'b0 : 1'bz;
    assign tx_clk = ref_clk;
    assign rx_clk = ref_clk;

    initial begin
        mdio_drive_low=0; one_count=0; bit_number=0; transaction=0;
        phy_address=0; register_address=0; opcode=0; write_shift=0;
        registers[0]=16'h1200; registers[1]=16'h786D;
        registers[2]=16'h2000; registers[3]=16'h5C90;
        registers[16]=16'h0015;
    end

    always @(posedge ref_clk or negedge reset_n) begin
        if(!reset_n) begin rxd<=0; rx_dv<=0; rxerr<=0; col<=0; crs<=0; end
        else begin rxd<=txd; rx_dv<=tx_en; rxerr<=0; col<=0; crs<=tx_en; end
    end

    always @(posedge mdc or negedge reset_n) begin
        if(!reset_n) begin
            one_count=0; bit_number=0; transaction=0; mdio_drive_low<=0;
        end else if(!transaction) begin
            if(mdio) one_count=one_count+1;
            else if(one_count>=32) begin transaction=1; bit_number=33; opcode=0; phy_address=0; register_address=0; end
            else one_count=0;
        end else begin
            if(bit_number==33 && mdio!=1'b1) transaction=0;
            if(bit_number==34) opcode[1]=mdio;
            if(bit_number==35) opcode[0]=mdio;
            if(bit_number>=36 && bit_number<=40) phy_address[40-bit_number]=mdio;
            if(bit_number>=41 && bit_number<=45) register_address[45-bit_number]=mdio;
            if(bit_number>=48 && bit_number<=63 && opcode==2'b01)
                write_shift[63-bit_number]=mdio;
            if(bit_number==63) begin
                if(opcode==2'b01 && phy_address==1) registers[register_address]=write_shift;
                transaction=0; one_count=0; mdio_drive_low<=0;
            end else bit_number=bit_number+1;
        end
    end

    always @(negedge mdc) begin
        if(transaction && opcode==2'b10 && phy_address==1) begin
            read_value = registers[register_address];
            if(bit_number==47) mdio_drive_low <= 1'b1;
            else if(bit_number>=48 && bit_number<=63) mdio_drive_low <= !read_value[63-bit_number];
            else mdio_drive_low <= 1'b0;
        end else mdio_drive_low <= 1'b0;
    end
endmodule
