// Selects one complete Ethernet frame at a time with fixed source priority.
module m5_tx_scheduler (
    input  logic       clk,
    input  logic       reset,
    input  logic       frame_busy,
    input  logic       frame_done,
    input  logic       arp_pending,
    input  logic       control_pending,
    input  logic       echo_pending,
    input  logic       camera_pending,
    input  logic       test_pending,
    output logic       frame_start,
    output logic [2:0] active_source,
    output logic       arp_grant,
    output logic       control_grant,
    output logic       echo_grant,
    output logic       camera_grant,
    output logic       test_grant
);
    localparam logic [2:0] SOURCE_NONE    = 3'd0;
    localparam logic [2:0] SOURCE_ARP     = 3'd1;
    localparam logic [2:0] SOURCE_CONTROL = 3'd2;
    localparam logic [2:0] SOURCE_ECHO    = 3'd3;
    localparam logic [2:0] SOURCE_CAMERA  = 3'd4;
    localparam logic [2:0] SOURCE_TEST    = 3'd5;

    always_ff @(posedge clk) begin
        if (reset) begin
            frame_start   <= 1'b0;
            active_source <= SOURCE_NONE;
            arp_grant     <= 1'b0;
            control_grant <= 1'b0;
            echo_grant    <= 1'b0;
            camera_grant  <= 1'b0;
            test_grant    <= 1'b0;
        end else begin
            frame_start   <= 1'b0;
            arp_grant     <= 1'b0;
            control_grant <= 1'b0;
            echo_grant    <= 1'b0;
            camera_grant  <= 1'b0;
            test_grant    <= 1'b0;

            if (frame_done)
                active_source <= SOURCE_NONE;

            if (!frame_busy && (active_source == SOURCE_NONE)) begin
                if (arp_pending) begin
                    active_source <= SOURCE_ARP;
                    arp_grant     <= 1'b1;
                    frame_start   <= 1'b1;
                end else if (control_pending) begin
                    active_source <= SOURCE_CONTROL;
                    control_grant <= 1'b1;
                    frame_start   <= 1'b1;
                end else if (echo_pending) begin
                    active_source <= SOURCE_ECHO;
                    echo_grant    <= 1'b1;
                    frame_start   <= 1'b1;
                end else if (camera_pending) begin
                    active_source <= SOURCE_CAMERA;
                    camera_grant  <= 1'b1;
                    frame_start   <= 1'b1;
                end else if (test_pending) begin
                    active_source <= SOURCE_TEST;
                    test_grant    <= 1'b1;
                    frame_start   <= 1'b1;
                end
            end
        end
    end
endmodule
