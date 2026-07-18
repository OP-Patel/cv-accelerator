// Transfers one coherent multi-bit status sample with a toggle handshake.
module m5_status_snapshot #(
    parameter integer WIDTH = 32
) (
    input  logic             destination_clk,
    input  logic             destination_reset,
    input  logic             request,
    output logic             busy,
    output logic             snapshot_valid,
    output logic [WIDTH-1:0] snapshot_data,
    input  logic             source_clk,
    input  logic             source_reset,
    input  logic [WIDTH-1:0] source_data
);
    logic request_toggle;
    logic acknowledge_toggle;
    logic acknowledge_seen;
    (* ASYNC_REG = "TRUE" *) logic [1:0] request_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] acknowledge_sync;
    logic [WIDTH-1:0] source_latched;
    logic [WIDTH-1:0] bus_meta, bus_sync;

    always_ff @(posedge source_clk or posedge source_reset) begin
        if (source_reset) begin
            request_sync       <= '0;
            acknowledge_toggle <= 1'b0;
            source_latched     <= '0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            if (request_sync[1] != acknowledge_toggle) begin
                source_latched     <= source_data;
                acknowledge_toggle <= request_sync[1];
            end
        end
    end

    always_ff @(posedge destination_clk) begin
        if (destination_reset) begin
            request_toggle   <= 1'b0;
            acknowledge_sync <= '0;
            bus_meta         <= '0;
            bus_sync         <= '0;
            snapshot_data    <= '0;
            snapshot_valid   <= 1'b0;
            acknowledge_seen <= 1'b0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
            bus_meta         <= source_latched;
            bus_sync         <= bus_meta;
            snapshot_valid   <= 1'b0;
            if (request && !busy)
                request_toggle <= ~request_toggle;
            if (acknowledge_sync[1] != acknowledge_seen) begin
                snapshot_data  <= bus_sync;
                snapshot_valid <= 1'b1;
                acknowledge_seen <= acknowledge_sync[1];
            end
        end
    end

    assign busy = (request_toggle != acknowledge_sync[1]);
endmodule
