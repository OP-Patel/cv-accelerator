// Measures complete-frame latency and sustained input cadence in the core domain.
module m7_core_metrics #(
    parameter integer IMAGE_WIDTH = 320,
    parameter integer IMAGE_HEIGHT = 240,
    parameter integer X_W = 9,
    parameter integer Y_W = 8
) (
    input  logic           clk,
    input  logic           reset,
    input  logic           clear,
    input  logic           in_valid,
    input  logic [X_W-1:0] in_x,
    input  logic [Y_W-1:0] in_y,
    input  logic           out_valid,
    input  logic [X_W-1:0] out_x,
    input  logic [Y_W-1:0] out_y,
    output logic [31:0]    last_latency_cycles,
    output logic [31:0]    last_frame_interval_cycles,
    output logic [31:0]    last_accepted_pixels,
    output logic [31:0]    last_produced_pixels,
    output logic [31:0]    last_valid_gap_cycles,
    output logic [31:0]    completed_frames
);
    logic [31:0] cycle_counter;
    logic [31:0] previous_start_cycle;
    logic previous_start_valid;
    logic [31:0] start_cycle_0, start_cycle_1;
    logic [1:0] pending_frames;
    logic input_frame_active;
    logic [31:0] input_pixels, output_pixels, gap_cycles;
    logic input_start, input_end, output_start, output_end;

    assign input_start = in_valid && (in_x == 0) && (in_y == 0);
    assign input_end = in_valid && (in_x == IMAGE_WIDTH-1) &&
                       (in_y == IMAGE_HEIGHT-1);
    assign output_start = out_valid && (out_x == 1) && (out_y == 1);
    assign output_end = out_valid && (out_x == IMAGE_WIDTH-2) &&
                        (out_y == IMAGE_HEIGHT-2);

    always_ff @(posedge clk) begin
        if (reset || clear) begin
            cycle_counter <= '0;
            previous_start_cycle <= '0;
            previous_start_valid <= 1'b0;
            start_cycle_0 <= '0;
            start_cycle_1 <= '0;
            pending_frames <= '0;
            input_frame_active <= 1'b0;
            input_pixels <= '0;
            output_pixels <= '0;
            gap_cycles <= '0;
            last_latency_cycles <= '0;
            last_frame_interval_cycles <= '0;
            last_accepted_pixels <= '0;
            last_produced_pixels <= '0;
            last_valid_gap_cycles <= '0;
            completed_frames <= '0;
        end else begin
            cycle_counter <= cycle_counter + 1'b1;

            if (input_start) begin
                if (previous_start_valid)
                    last_frame_interval_cycles <= cycle_counter - previous_start_cycle;
                previous_start_cycle <= cycle_counter;
                previous_start_valid <= 1'b1;
                if (pending_frames == 0) begin
                    start_cycle_0 <= cycle_counter;
                    pending_frames <= 1;
                end else if (pending_frames == 1) begin
                    start_cycle_1 <= cycle_counter;
                    pending_frames <= 2;
                end
                input_frame_active <= 1'b1;
                input_pixels <= 1;
                gap_cycles <= 0;
            end else if (in_valid && input_frame_active) begin
                input_pixels <= input_pixels + 1'b1;
            end else if (input_frame_active) begin
                gap_cycles <= gap_cycles + 1'b1;
            end

            if (input_end) begin
                input_frame_active <= 1'b0;
                last_accepted_pixels <= input_pixels + 1'b1;
                last_valid_gap_cycles <= gap_cycles;
            end

            if (output_start)
                output_pixels <= 1;
            else if (out_valid)
                output_pixels <= output_pixels + 1'b1;

            if (output_end) begin
                last_produced_pixels <= output_pixels + 1'b1;
                completed_frames <= completed_frames + 1'b1;
                if (pending_frames != 0) begin
                    last_latency_cycles <= cycle_counter - start_cycle_0 + 1'b1;
                    if (pending_frames == 2) begin
                        start_cycle_0 <= start_cycle_1;
                        pending_frames <= 1;
                    end else begin
                        pending_frames <= 0;
                    end
                end
            end
        end
    end
endmodule
