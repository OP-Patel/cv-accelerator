# Milestone 4 handoff and Milestone 5 camera-over-Ethernet plan

## Handoff status

Milestone 4 is functionally complete as of July 17, 2026. The Arty A7-100T
proved the complete standalone Ethernet path before camera integration:

1. the FPGA generated the DP83848J reference clock and reset sequence;
2. MDIO returned `PHY=2000:5C90` at PHY address 1;
3. the link negotiated at 100 Mb/s full duplex;
4. deterministic raw Ethernet passed in both directions;
5. the FPGA answered ARP for `192.168.10.2`;
6. UDP echo on port 4000 returned exact 46-byte payloads;
7. the sustained run crossed 10,000 UDP exchanges;
8. final UART status was `BAD=0 DROP=0 ERR=0`;
9. all five Milestone 4 XSim targets passed;
10. routed timing passed with WNS `1.477 ns` and WHS `0.057 ns`, and routed
    DRC had zero findings.

The final physical line was:

```text
[2026-07-17 20:51:38] [PASS:PASS] M4 PHY=2000:5C90 LINK=1 SPD=100 DUP=F TX=00002714 RX=00002957 BAD=00000000 DROP=00000000 ERR=0000
```

## Authoritative Milestone 4 artifacts

- `milestone4_ethernet_logic_walkthrough.md`: implemented MAC/PHY behavior
- `milestone4_ethernet_hardware_validation.md`: acceptance table and repeat procedure
- `milestone4_hardware_results.txt`: concise raw physical evidence
- `milestone4_ethernet_debugging_postmortem.md`: host/setup failure sequence
- `milestone4_simulation_results.txt`: five passing XSim targets
- `timing_summary_milestone4.rpt`: routed timing
- `utilization_milestone4.rpt`: implemented utilization
- `cdc_milestone4.rpt`: CDC findings requiring disposition
- `drc_milestone4.rpt`: zero routed DRC findings
- `milestone4_bitstream_sha256.txt`: tested bitstream digest

Keep `arty_m4_ethernet_top.sv` and its dedicated project runnable throughout
Milestone 5. It is the known-good network baseline and the fastest way to
separate an integration failure from a PHY/MAC failure.

## Known limitations carried forward

- Physical validation covered 100 Mb/s full duplex. A deliberate 10 Mb/s
  partner was not tested.
- The FPGA is a fixed-address endpoint. It does not implement DHCP, routing,
  fragmentation, or a general network stack.
- M4's UDP checksum is zero, which is legal for IPv4. Ethernet FCS and the IPv4
  header checksum remain active.
- M4's wide UART status bus is diagnostic and can tear across clock domains.
  It is not data-plane control, but M5 needs a coherent snapshot handshake.
- Vivado's CDC report flags inferred async-FIFO RAM paths, combinational reset
  inputs, Gray-pointer buses, and diagnostic crossings. Functional hardware
  evidence is good, but M5 must explicitly classify or eliminate each finding.
- The current `interfaces` helper in `ethernet_test.py` is incompatible with
  the installed Scapy/libpcap interface naming. The passing adapter name is
  `Ethernet 2`.

## Milestone 5 objective

Connect the completed Milestone 3 camera/Sobel path to the completed Milestone
4 Ethernet path and reconstruct processed camera frames on the host.

The default stream is the cropped 8-bit Sobel output:

```text
camera 320x240 RGB565
  -> grayscale 320x240
  -> Sobel 318x238, 75,684 bytes per frame
  -> packet FIFO and UDP packetizer
  -> DP83848J 100 Mb/s Ethernet
  -> host frame reassembly and validation
```

Grayscale 320x240 streaming remains a diagnostic mode. Raw RGB565 transport,
compression, display polish, and camera control over the network are not
required for initial acceptance.

## Milestone 5 completion contract

Milestone 5 is complete when one integrated bitstream can:

1. configure the physical OV7670 as already proven by M3;
2. discover and link the DP83848J as already proven by M4;
3. preserve M4 ARP and UDP echo behavior on port 4000;
4. accept a host start/stop control message on UDP port 4001;
5. learn the host MAC, IPv4 address, and UDP destination port from that control
   packet instead of hard-coding the host MAC;
6. stream complete Sobel frames as non-fragmented UDP datagrams;
7. let the host detect every missing, duplicate, reordered, malformed, or
   CRC-mismatched packet;
8. reconstruct exact 318x238 frames and save a dependency-free PGM image;
9. run at least 300 consecutive live frames without camera, FIFO, Ethernet,
   packet, or reassembly errors;
10. pass integrated simulation, synthesis, timing, CDC review, and physical
    validation while leaving the M3 and M4 standalone regressions passing.

## Network identity and session model

Preserve the M4 identity:

```text
FPGA MAC:        02:00:00:00:00:01
FPGA IPv4:       192.168.10.2
Host IPv4:       192.168.10.1/24
M4 echo port:    4000
M5 control port: 4001
```

The FPGA cannot send useful unicast camera traffic until it knows the host
MAC. Do not add a hard-coded ASIX adapter MAC. Use this session sequence:

1. the host binds UDP port 4001 and sends an M5 START control packet to
   `192.168.10.2:4001`;
2. normal host ARP resolves the FPGA exactly as in M4;
3. the FPGA validates the UDP/IP lengths and destination port;
4. the FPGA saves the request's source MAC, source IPv4 address, and source UDP
   port as one coherent session descriptor;
5. the FPGA sends an ACK and then camera datagrams to that learned endpoint;
6. STOP, link loss, PHY restart, or complete reset invalidates the session.

Suggested fixed 12-byte control payload, all multi-byte fields big-endian:

| Byte | Field |
|---:|---|
| 0..3 | ASCII `M5CT` |
| 4 | version, initially 1 |
| 5 | opcode: 1 START, 2 STOP, 3 PING |
| 6 | stream: 0 Sobel, 1 grayscale |
| 7 | flags, initially zero |
| 8..11 | requested frame count; zero means continuous |

Reject other lengths, versions, opcodes, or stream IDs and increment a
separate control-protocol error counter.

## Camera UDP payload contract

Use at most 1,024 image bytes per datagram. A 32-byte M5 header plus 1,024
image bytes is safely below the IPv4 non-fragmented UDP payload limit of 1,472
bytes on standard Ethernet.

All multi-byte header fields are unsigned and big-endian:

| Byte | Width | Field |
|---:|---:|---|
| 0 | 4 | ASCII magic `M5CV` |
| 4 | 1 | protocol version, initially 1 |
| 5 | 1 | stream ID: 0 Sobel, 1 grayscale |
| 6 | 1 | flags: bit 0 FIRST, bit 1 LAST, bit 2 DISCONTINUITY |
| 7 | 1 | header size, fixed at 32 |
| 8 | 4 | camera frame sequence |
| 12 | 2 | packet index within frame, starting at zero |
| 14 | 2 | total packet count for this frame |
| 16 | 4 | byte/pixel offset within the raster stream |
| 20 | 2 | image payload length in this datagram |
| 22 | 2 | output width |
| 24 | 2 | output height |
| 26 | 2 | reserved, transmit zero and require zero |
| 28 | 4 | CRC-32 of this datagram's image payload |
| 32 | up to 1,024 | raster-ordered 8-bit pixels |

For Sobel mode:

- width: 318;
- height: 238;
- bytes per frame: 75,684;
- packets per frame: 74;
- final packet payload: 932 bytes.

For grayscale mode:

- width: 320;
- height: 240;
- bytes per frame: 76,800;
- packets per frame: 75;
- every packet payload: 1,024 bytes.

Do not use IPv4 fragmentation. A datagram must represent one contiguous raster
range and must never cross a frame boundary.

## Throughput budget

The 8-bit Sobel stream is 75,684 bytes per frame. At 30 frames/s its image
payload rate is about 2.27 MB/s, or 18.16 Mb/s. Seventy-four datagrams per frame
add Ethernet, IPv4, UDP, M5 header, preamble, and inter-packet overhead, but the
result remains comfortably below a 100 Mb/s link.

The difficult case is short-term burst rate during active camera lines, not
average bandwidth. The camera/convolution pipeline has no backpressure and
must never be stalled by Ethernet. Buffer sizing must therefore be based on
measured maximum occupancy across active lines and blanking intervals, not
only the average frame rate.

## Recommended integrated architecture

### Preserve the proven front end

Reuse without changing behavior:

- `camera_xclk.sv` and SCCB initialization;
- `dvp_rgb565_capture.sv`;
- `camera_stream_cdc.sv` from PCLK to 100 MHz;
- `camera_stream_adapter.sv`;
- `conv_pipeline_top.sv` and its exact coordinate semantics.

Tap `sobel_valid/sobel_x/sobel_y/sobel_pixel` for the default stream and
`gray_valid/gray_x/gray_y/gray_pixel` for diagnostic mode. Do not recalculate
Sobel inside the network packetizer.

### Add one explicit stream FIFO

Write `{frame markers, pixel byte}` in the 100 MHz processing domain and read
it in the Ethernet packet-generation domain. Prefer `xpm_fifo_async` so Vivado
recognizes the crossing. Expose current and maximum occupancy plus overflow.

There is no legal backpressure path to the camera. If overflow occurs:

1. set a sticky overflow flag;
2. abandon the rest of the current frame;
3. do not transmit a malformed partial packet as if it were complete;
4. resume only at the next clean frame start;
5. set DISCONTINUITY on the next transmitted frame;
6. increment dropped-frame and dropped-pixel counters.

### Add a non-preemptive TX scheduler

Select a source only when the current Ethernet frame is complete. Suggested
priority:

1. ARP replies;
2. M5 control ACKs and M4 UDP echo replies;
3. camera datagrams;
4. manual/continuous raw M4 debug frames.

Once selected, a source owns the transmitter until its frame is complete.
Never interleave bytes from two sources. The scheduler should pass a coherent
descriptor containing destination MAC/IP/ports, payload length, and source ID
before the first byte is requested.

### Make status snapshots coherent

For counters crossing into the 100 MHz UART domain, use a toggle-based request
and acknowledge handshake:

1. UART domain toggles a snapshot request;
2. source domain latches all related fields together and toggles acknowledge;
3. UART domain synchronizes acknowledge, then samples the stable latched bus;
4. source keeps the bus unchanged until the next request.

Do not use a free-running wide bus synchronized bit by bit for acceptance
counters.

## Proposed controls and UART

- `BTN0`: complete integrated reset
- `BTN1`: restart camera initialization and PHY discovery
- `BTN2`: clear camera, stream, packet, FIFO, and Ethernet errors/counters
- `BTN3`: request a coherent UART snapshot; when continuous streaming is off,
  arm one complete frame for transmission
- `SW0`: OV7670 color bars on the next camera initialization
- `SW1`: 0 Sobel stream, 1 grayscale diagnostic stream
- `SW2`: local streaming enable gate; a valid host session is still required
- `SW3`: freeze the most recently completed frame/status snapshot
- `LD4`: heartbeat
- `LD5`: camera configured and Ethernet linked
- `LD6`: camera packet activity
- `LD7`: any sticky camera/network/FIFO error

Suggested compact UART shape:

```text
[PASS:PASS:PASS] M5 CAM=7673 LINK=1 SPD=100 MODE=S F=0000012C PKT=000056B8 BYTE=015A1E20 DROP=00000000 ERR=0000
```

The three PASS fields represent camera configuration, network/PHY status, and
stream integrity. Keep raw counters authoritative and hexadecimal.

## Phased implementation plan

### Phase 0: freeze baselines and clean contracts

- Keep M3 and M4 bitstreams, scripts, and tests runnable.
- Add the exact M5 control and camera-packet formats to a hardware contract.
- Classify every M4 CDC finding.
- Replace diagnostic multi-bit sampling with a coherent snapshot handshake.
- Decide the stream FIFO primitive/depth and document the overflow policy.

Acceptance: no M3/M4 regression changes and no ambiguous packet or reset
semantics remain.

### Phase 1: packetizer and host reassembler without camera hardware

- Build a standalone M5 packetizer driven by a synthetic raster stream.
- Build a Python receiver that binds `192.168.10.1:4001`, sends START, validates
  headers/CRC/order, reconstructs frames, and writes binary PGM files.
- Test full and partial final datagrams, frame boundaries, STOP, and restart.

Acceptance: generated Sobel-sized and grayscale-sized frames round-trip through
the RTL format and match a software model byte for byte.

### Phase 2: integrated simulation

- Create an M5 top combining the camera model, M3 processing, packetizer, M4
  scheduler, and DP83848 MII model.
- Drive deterministic OV7670 color bars and compare reconstructed Sobel bytes
  against the existing golden model.
- Inject FIFO pressure, link loss, malformed control packets, bad FCS, resets,
  and consecutive frames.

Acceptance: exact packet/frame counts and CRCs, clean recovery at the next
frame boundary, and no malformed Ethernet transmission.

### Phase 3: synthesis and timing

- Merge camera and Ethernet constraints into a dedicated M5 XDC.
- Confirm no pin conflicts and preserve both 24 MHz camera XCLK and 25 MHz PHY
  reference-clock generation.
- Run synthesis, implementation, timing, DRC, and detailed CDC.
- Treat unexplained critical CDC findings as blocking for M5.

Acceptance: nonnegative setup/hold timing, zero DRC findings, and every CDC
crossing implemented by an approved single-bit sync, handshake, or async FIFO.

### Phase 4: deterministic hardware bring-up

- Program the integrated bitstream with camera color bars enabled.
- First prove M4 ARP/UDP echo still passes on port 4000.
- Start one Sobel frame on port 4001 and save it as PGM.
- Compare dimensions, packet count, payload byte count, and CRC with the M3
  color-bar expectations.
- Run 100 consecutive color-bar frames.

Acceptance: 74 packets and 75,684 image bytes per Sobel frame, no reassembly
gaps, and zero camera/network/FIFO errors.

### Phase 5: live camera sustained run

- Disable color bars and stream the live lens image.
- Run at least 300 consecutive frames.
- Record host missing/duplicate/reordered/CRC counters, FPGA FIFO maximum
  occupancy, dropped frames/pixels, and final UART status.
- Save a short `.pcapng`, one reconstructed PGM, the host transcript, and UART
  transcript.

Acceptance: all 300 frames reconstruct to 318x238, host integrity counters are
zero, FPGA `DROP=0`, and all combined sticky error flags are zero.

## Required simulations

At minimum add self-checking tests for:

- exact 32-byte M5 header layout and endianness;
- 1,024-byte packet boundary and 932-byte Sobel tail packet;
- 74-packet Sobel and 75-packet grayscale frames;
- frame sequence, packet index, pixel offset, FIRST/LAST flags;
- payload CRC-32 and deliberate corruption;
- START/STOP/PING validation and learned host descriptor;
- no session, link loss, session replacement, and reset;
- scheduler priority and non-preemption;
- stream FIFO normal, almost-full, overflow, frame discard, and recovery;
- camera valid gaps and back-to-back frames;
- integrated color-bar camera through Sobel through UDP bytes;
- coherent UART snapshots during active traffic;
- preserved M4 ARP and UDP echo behavior.

## Expected new files

```text
constraints/arty_a7_m5_camera_ethernet.xdc
rtl/integration/m5_control_receiver.sv
rtl/integration/m5_stream_fifo.sv
rtl/integration/m5_stream_packetizer.sv
rtl/integration/m5_tx_scheduler.sv
rtl/integration/m5_status_snapshot.sv
rtl/debug/m5_uart_reporter.sv
rtl/top/arty_m5_camera_ethernet_top.sv
sim/tb/tb_m5_control_receiver.sv
sim/tb/tb_m5_stream_packetizer.sv
sim/tb/tb_m5_tx_scheduler.sv
sim/tb/tb_m5_camera_udp.sv
scripts/run_m5_simulations.tcl
scripts/check_m5_synthesis.tcl
scripts/build_m5_bitstream.tcl
scripts/python/camera_udp_receiver.py
docs/milestone5_camera_ethernet_contract.md
docs/milestone5_camera_ethernet_logic_walkthrough.md
docs/milestone5_hardware_validation.md
```

Use a dedicated `vivado_project_m5` so changing the integrated top or combined
constraints cannot silently alter the known-good M3 or M4 projects.

## Deliberately outside Milestone 5

- JPEG, H.264, or other image compression
- raw RGB565 transport as the primary acceptance stream
- DHCP, DNS, TCP, HTTP, or a general-purpose IP stack
- browser streaming or a polished GUI
- DDR frame buffering
- retransmission or guaranteed delivery over UDP
- multiple simultaneous hosts
- Gigabit Ethernet

The milestone is about a clear, measurable hardware integration: validated
camera pixels enter the validated Sobel core, complete processed frames cross
the validated 100 Mb/s Ethernet path, and a small host tool proves exactly what
arrived.
