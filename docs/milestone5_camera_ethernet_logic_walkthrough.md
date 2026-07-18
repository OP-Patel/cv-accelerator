# Milestone 5 camera-over-Ethernet logic walkthrough

## Implemented data path

`arty_m5_camera_ethernet_top.sv` combines the proven M3 and M4 paths. The
OV7670 is initialized over SCCB, captured as 320x240 RGB565, crossed from PCLK
to 100 MHz, converted to grayscale, and processed by the existing Sobel core.
The selected Sobel or grayscale byte stream enters `m5_stream_fifo.sv`, a
32,768-entry `xpm_fifo_async`, and is read in the Ethernet receive clock
domain.

`m5_stream_packetizer.sv` collects at most 1,024 pixels, calculates payload
CRC-32, and exposes a complete Ethernet/IPv4/UDP frame image. It cannot mix
frames or emit an incomplete chunk. `m5_tx_scheduler.sv` arbitrates complete
frames from the existing ARP and UDP echo responders, the new control ACK
generator, and the camera packetizer. The existing Ethernet encoder, async TX
FIFO, and MII transmitter then drive the DP83848J.

## Session and recovery behavior

`m5_control_receiver.sv` accepts only the fixed 12-byte `M5CT` message on UDP
port 4001. A valid START atomically records the sender's MAC, IP, and UDP port.
STOP clears the session and PING only requests an acknowledgement. Link loss
also clears the learned session.

The stream FIFO tracks frame boundaries because the upstream camera pipeline
cannot be stalled. Overflow abandons the current frame and suppresses data
until the next frame start. Drop counters remain visible and the next clean
frame carries the DISCONTINUITY flag.

## Status path

`m5_status_snapshot.sv` uses request/acknowledge toggles. The Ethernet domain
latches its related counters together, acknowledges the request, and holds the
bus stable while the 100 MHz domain samples it. `m5_uart_reporter.sv` combines
that snapshot with camera identity and synchronized error state, avoiding the
free-running diagnostic bus used by the earlier standalone Ethernet top.

## Host tool

`scripts/python/camera_udp_receiver.py` binds the host's port 4001, sends
START, checks the ACK, validates every M5 header and CRC, detects missing,
duplicate, reordered, and malformed packets, reconstructs the raster, and
writes a dependency-free binary PGM file. It sends STOP on exit unless
`--no-stop` is selected.

## Build separation

Milestone 5 uses `vivado_project_m5` and
`constraints/arty_a7_m5_camera_ethernet.xdc`. The M3 and M4 tops, constraints,
projects, and scripts are not replaced, so either standalone baseline remains
available for fault isolation.
