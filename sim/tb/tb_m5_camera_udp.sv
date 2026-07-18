`timescale 1ns/1ps
// Small end-to-end deterministic raster -> Sobel -> async FIFO -> UDP test.
module tb_m5_camera_udp;
    localparam integer WIDTH=8;
    localparam integer HEIGHT=6;
    localparam integer X_W=3;
    localparam integer Y_W=3;
    logic system_clk=0, network_clk=0, reset=1;
    logic in_valid=0;
    logic [X_W-1:0] in_x=0;
    logic [Y_W-1:0] in_y=0;
    logic [7:0] in_gray=0;
    logic sobel_valid;
    logic [X_W-1:0] sobel_x;
    logic [Y_W-1:0] sobel_y;
    logic [7:0] sobel_pixel;
    logic [31:0] unused0,unused1,unused2,unused3,protocol_errors,unused4;
    logic fifo_read, fifo_valid, fifo_start, fifo_end, fifo_discontinuity, fifo_id;
    logic [7:0] fifo_pixel;
    logic fifo_overflow;
    logic [31:0] dropped_frames,dropped_pixels;
    logic [15:0] maximum_occupancy;
    logic session_active=0,session_restart=0;
    logic packet_ready,packet_done=0,stream_complete;
    logic [10:0] frame_index=0,frame_length;
    logic [7:0] frame_data;
    logic [31:0] frames_sent,packets_sent,bytes_sent,packet_errors;
    integer x,y,packet_number,payload_index,reconstructed_count;
    always #5 system_clk=~system_clk;
    always #20 network_clk=~network_clk;

    conv_pipeline_top #(
        .IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT),.X_W(X_W),.Y_W(Y_W)
    ) u_pipeline(
        .clk(system_clk),.reset(reset),.in_valid(in_valid),.in_x(in_x),
        .in_y(in_y),.in_gray(in_gray),.out_valid(sobel_valid),
        .out_x(sobel_x),.out_y(sobel_y),.out_pixel(sobel_pixel),
        .accepted_input_pixels(unused0),.valid_output_pixels(unused1),
        .frames_started(unused2),.frames_completed(unused3),
        .protocol_errors(protocol_errors),.output_checksum(unused4)
    );
    m5_stream_fifo #(.FIFO_DEPTH(64)) u_fifo(
        .reset(reset),.write_clk(system_clk),.clear_errors(1'b0),
        .stream_enable(1'b1),.write_valid(sobel_valid),
        .write_frame_start(sobel_valid&&sobel_x==1&&sobel_y==1),
        .write_frame_end(sobel_valid&&sobel_x==WIDTH-2&&sobel_y==HEIGHT-2),
        .write_stream_id(1'b0),.write_pixel(sobel_pixel),.read_clk(network_clk),
        .read_enable(fifo_read),.read_valid(fifo_valid),.read_frame_start(fifo_start),
        .read_frame_end(fifo_end),.read_discontinuity(fifo_discontinuity),
        .read_stream_id(fifo_id),.read_pixel(fifo_pixel),
        .overflow_sticky(fifo_overflow),.dropped_frames(dropped_frames),
        .dropped_pixels(dropped_pixels),.maximum_occupancy(maximum_occupancy)
    );
    m5_stream_packetizer #(
        .IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT),.MAX_IMAGE_BYTES(8)
    ) u_packetizer(
        .clk(network_clk),.reset(reset),.clear_errors(1'b0),
        .session_active(session_active),.session_restart(session_restart),
        .session_stream_id(1'b0),.requested_frame_count(32'd1),
        .host_mac(48'h10_20_30_40_50_60),.host_ip(32'hC0A8_0A01),
        .host_port(16'd5000),.fifo_valid(fifo_valid),
        .fifo_frame_start(fifo_start),.fifo_frame_end(fifo_end),
        .fifo_discontinuity(fifo_discontinuity),.fifo_stream_id(fifo_id),
        .fifo_pixel(fifo_pixel),.fifo_read_enable(fifo_read),
        .packet_ready(packet_ready),.packet_done(packet_done),
        .frame_index(frame_index),.frame_length(frame_length),.frame_data(frame_data),
        .stream_complete(stream_complete),.frames_sent(frames_sent),
        .packets_sent(packets_sent),.bytes_sent(bytes_sent),.packet_errors(packet_errors)
    );

    initial begin
        reconstructed_count=0; packet_number=0;
        repeat(8) @(posedge system_clk); @(negedge system_clk); reset=0;
        @(posedge network_clk); session_active=1; session_restart=1;
        @(posedge network_clk); session_restart=0;
        repeat(100) @(posedge network_clk);

        for(y=0;y<HEIGHT;y=y+1) begin
            for(x=0;x<WIDTH;x=x+1) begin
                @(negedge system_clk);
                in_valid=1; in_x=x; in_y=y; in_gray=x*10+y;
            end
        end
        @(negedge system_clk); in_valid=0;
    end

    initial begin
        wait(!reset);
        forever begin
            wait(packet_ready);
            for(payload_index=0;payload_index<8;payload_index=payload_index+1) begin
                frame_index=74+payload_index; #1;
                if(frame_data!=8'd88)
                    $fatal(1,"Sobel byte %0d was %0d instead of 88",
                           reconstructed_count,frame_data);
                reconstructed_count=reconstructed_count+1;
            end
            packet_done=1; @(posedge network_clk); #1; packet_done=0;
            packet_number=packet_number+1;
            if(packet_number==3) begin
                #1;
                if(reconstructed_count!=24 || frames_sent!=1 || packets_sent!=3 ||
                   bytes_sent!=24 || packet_errors!=0 || protocol_errors!=0 ||
                   fifo_overflow || dropped_frames!=0 || dropped_pixels!=0)
                    $fatal(1,"integrated Sobel/UDP totals failed");
                $display("PASS: tb_m5_camera_udp");
                $finish;
            end
        end
    end
    initial begin
        #2_000_000;
        $fatal(1,"integrated camera/UDP test timed out: sobel=%0d fifo_valid=%0b wr_busy=%0b full=%0b in_frame=%0b payload=%0d ready=%0b errors=%0d drops=%0d",
               unused1,fifo_valid,u_fifo.write_reset_busy,u_fifo.fifo_full,
               u_packetizer.in_frame,u_packetizer.payload_count,
               packet_ready,packet_errors,dropped_pixels);
    end
endmodule
