// Exposes camera frame cadence and raw PCLK/HREF activity without changing capture.
module camera_timing_monitor (
    input  logic        system_clk,
    input  logic        system_reset,
    input  logic        cam_pclk,
    input  logic        camera_reset,
    input  logic        clear,
    input  logic        cam_vsync,
    input  logic        cam_href,
    output logic [31:0] frame_period_system_cycles,
    output logic [31:0] frame_pclk_edges,
    output logic [15:0] line_pclk_edges,
    output logic [31:0] active_bytes,
    output logic [15:0] active_lines,
    // Stable source-domain bus consumed by a coherent CDC snapshot.
    output logic [127:0] source_snapshot
);
    (* ASYNC_REG = "TRUE" *) logic [2:0] vsync_system_sync;
    logic [31:0] system_period_counter;
    logic system_frame_seen;
    logic previous_vsync, previous_href;
    logic [31:0] pclk_frame_counter, active_byte_counter;
    logic [15:0] pclk_line_counter, active_line_counter;
    logic line_seen;

    always_ff @(posedge system_clk) begin
        if (system_reset) begin
            vsync_system_sync <= '0;
            system_period_counter <= '0;
            system_frame_seen <= 1'b0;
            frame_period_system_cycles <= '0;
        end else begin
            vsync_system_sync <= {vsync_system_sync[1:0], cam_vsync};
            system_period_counter <= system_period_counter + 1'b1;
            if (clear) begin
                system_frame_seen <= 1'b0;
                frame_period_system_cycles <= '0;
            end
            if (vsync_system_sync[1] && !vsync_system_sync[2]) begin
                if (system_frame_seen)
                    frame_period_system_cycles <= system_period_counter;
                system_period_counter <= 0;
                system_frame_seen <= 1'b1;
            end
        end
    end

    always_ff @(posedge cam_pclk) begin
        if (camera_reset) begin
            previous_vsync <= 1'b0;
            previous_href <= 1'b0;
            pclk_frame_counter <= '0;
            pclk_line_counter <= '0;
            active_byte_counter <= '0;
            active_line_counter <= '0;
            line_seen <= 1'b0;
            frame_pclk_edges <= '0;
            line_pclk_edges <= '0;
            active_bytes <= '0;
            active_lines <= '0;
        end else begin
            pclk_frame_counter <= pclk_frame_counter + 1'b1;
            pclk_line_counter <= pclk_line_counter + 1'b1;
            if (cam_href)
                active_byte_counter <= active_byte_counter + 1'b1;
            if (previous_href && !cam_href)
                active_line_counter <= active_line_counter + 1'b1;

            if (cam_href && !previous_href) begin
                if (line_seen)
                    line_pclk_edges <= pclk_line_counter;
                pclk_line_counter <= 0;
                line_seen <= 1'b1;
            end

            if (cam_vsync && !previous_vsync) begin
                frame_pclk_edges <= pclk_frame_counter;
                active_bytes <= active_byte_counter;
                active_lines <= active_line_counter;
                pclk_frame_counter <= 0;
                active_byte_counter <= 0;
                active_line_counter <= 0;
                line_seen <= 1'b0;
            end

            previous_vsync <= cam_vsync;
            previous_href <= cam_href;
        end
    end

    // Keep all PCLK-derived values together; consumers must not sample the
    // individual counters directly from another clock domain.
    always_comb begin
        source_snapshot = {
            frame_pclk_edges,
            active_bytes,
            active_lines,
            line_pclk_edges,
            32'd0
        };
    end
endmodule
