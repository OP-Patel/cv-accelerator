`timescale 1ns/1ps

// Generates camera-like RGB565 frames with independent PCLK and blanking gaps.
module dvp_camera_model #(
    parameter integer IMAGE_WIDTH = 8,
    parameter integer IMAGE_HEIGHT = 8,
    parameter integer PCLK_HALF_PERIOD_NS = 7
) (
    output logic       cam_pclk = 1'b0,
    output logic       cam_vsync = 1'b1,
    output logic       cam_href = 1'b0,
    output logic [7:0] cam_d = 8'd0
);
    always #(PCLK_HALF_PERIOD_NS) cam_pclk = ~cam_pclk;

    // Produces a deterministic coordinate-encoded RGB565 test pixel.
    function automatic logic [15:0] coordinate_pixel(input integer x, input integer y);
        coordinate_pixel = ((x & 31) << 11) | ((y & 63) << 5) | ((x + y) & 31);
    endfunction

    // Presents one data byte before the next rising PCLK capture edge.
    task automatic send_byte(input logic [7:0] value);
        begin
            cam_d = value;
            @(posedge cam_pclk);
            @(negedge cam_pclk);
        end
    endtask

    // Starts in the middle of a line, as real hardware can when capture reset
    // is released while the free-running camera is already transmitting.
    task automatic send_partial_line_before_sync(input integer byte_count);
        integer index;
        begin
            cam_vsync = 1'b0;
            cam_href = 1'b1;
            for (index = 0; index < byte_count; index = index + 1) begin
                send_byte(index[7:0]);
            end
            cam_href = 1'b0;
            repeat (3) @(posedge cam_pclk);
        end
    endtask

    // Sends one complete frame; low_byte_first exercises COM3 byte swapping.
    task automatic send_frame(input logic low_byte_first);
        integer x, y;
        logic [15:0] pixel;
        begin
            cam_vsync = 1'b1;
            cam_href = 1'b0;
            repeat (4) @(posedge cam_pclk);
            @(negedge cam_pclk);
            cam_vsync = 1'b0;
            repeat (3) @(posedge cam_pclk);

            for (y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
                @(negedge cam_pclk);
                cam_href = 1'b1;
                for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                    pixel = coordinate_pixel(x, y);
                    if (low_byte_first) begin
                        send_byte(pixel[7:0]);
                        send_byte(pixel[15:8]);
                    end else begin
                        send_byte(pixel[15:8]);
                        send_byte(pixel[7:0]);
                    end
                end
                cam_href = 1'b0;
                repeat (3) @(posedge cam_pclk);
            end

            @(negedge cam_pclk);
            cam_vsync = 1'b1;
            repeat (4) @(posedge cam_pclk);
        end
    endtask

    // Sends a frame whose selected line has one unpaired active byte.
    task automatic send_odd_byte_frame(input integer bad_line);
        integer x, y;
        logic [15:0] pixel;
        begin
            cam_vsync = 1'b1;
            cam_href = 1'b0;
            repeat (4) @(posedge cam_pclk);
            @(negedge cam_pclk);
            cam_vsync = 1'b0;
            repeat (3) @(posedge cam_pclk);

            for (y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
                @(negedge cam_pclk);
                cam_href = 1'b1;
                for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                    pixel = coordinate_pixel(x, y);
                    send_byte(pixel[15:8]);
                    send_byte(pixel[7:0]);
                end
                if (y == bad_line) send_byte(8'haa);
                cam_href = 1'b0;
                repeat (3) @(posedge cam_pclk);
            end

            @(negedge cam_pclk);
            cam_vsync = 1'b1;
            repeat (4) @(posedge cam_pclk);
        end
    endtask
endmodule
