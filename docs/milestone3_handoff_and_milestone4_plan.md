# Milestone 3 handoff and Milestone 4 Ethernet bring-up plan

## Handoff status

Milestone 3 is functionally complete. The physical OV7670 path configured and
processed 306 consecutive 320x240 frames with exact input/output counts,
stable CRCs, and no reported error. The final evidence is recorded in:

- `milestone3_camera_hardware_validation.md`;
- `milestone3_hardware_results.txt`;
- `milestone3_camera_debugging_postmortem.md`;
- `milestone3_uart_capture.txt`.

Milestone 4 RTL has now been implemented from this contract. The checkout has
the 10/100 MII MAC/PHY logic, constraints, focused testbenches, host packet
tool, and build targets. Simulation, implementation, timing review, and
physical hardware evidence are still required before Milestone 4 is complete.

## Milestone 4 objective

Bring up the Arty A7's onboard Ethernet PHY and prove reliable bidirectional
packet transfer using a synthetic payload. Keep the camera and Sobel pipeline
out of the data path until the Ethernet transport works independently.

Milestone 4 is complete when the board can:

1. generate the PHY's 25 MHz reference clock and reset it cleanly;
2. read the expected PHY identity over MDIO at address 1;
3. report link, negotiated speed, and duplex over UART;
4. transmit valid Ethernet frames that a host script receives and verifies;
5. receive host Ethernet frames and verify their length, sequence, and data;
6. exchange fixed-address ARP and UDP packets with the host;
7. sustain a bidirectional packet test with zero CRC, sequence, FIFO, or
   framing errors;
8. pass simulation, implementation timing, and physical hardware validation.

Full camera-frame transport is Milestone 5 integration, not Milestone 4.

## Board hardware contract

The Arty A7 carries a Texas Instruments DP83848J 10/100 Mb/s PHY. It is wired
in 4-bit MII mode. Digilent documents these power-on defaults:

- MII mode;
- auto-negotiation enabled for 10/100 capabilities;
- PHY address `00001`;
- LED mode 2.

The FPGA must drive a 25 MHz clock to `ETH_REF_CLK`. The PHY returns separate
MII receive and transmit clocks. Do not treat this interface as RMII or RGMII.

Primary references:

- Digilent Arty reference manual, section 6:
  <https://digilent.com/reference/_media/reference/programmable-logic/arty/arty_rm.pdf>
- Digilent Arty A7-100 Master XDC:
  <https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc>
- Texas Instruments DP83848J datasheet:
  <https://www.ti.com/lit/ds/symlink/dp83848j.pdf>

## Ethernet pin assignment

Create `constraints/arty_a7_ethernet.xdc` from the Digilent Master XDC. The
reviewed signal list is:

| RTL port | Package pin | Direction at FPGA | Meaning |
|---|---:|---|---|
| `eth_col` | `D17` | input | collision detect |
| `eth_crs` | `G14` | input | carrier sense |
| `eth_mdc` | `F16` | output | MDIO clock |
| `eth_mdio` | `K13` | bidirectional | MDIO data |
| `eth_ref_clk` | `G18` | output | 25 MHz PHY reference |
| `eth_rstn` | `C16` | output | active-low PHY reset |
| `eth_rx_clk` | `F15` | input | MII receive clock |
| `eth_rx_dv` | `G16` | input | receive data valid |
| `eth_rxd[0]` | `D18` | input | receive data bit 0 |
| `eth_rxd[1]` | `E17` | input | receive data bit 1 |
| `eth_rxd[2]` | `E18` | input | receive data bit 2 |
| `eth_rxd[3]` | `G17` | input | receive data bit 3 |
| `eth_rxerr` | `C17` | input | receive error |
| `eth_tx_clk` | `H16` | input | MII transmit clock |
| `eth_tx_en` | `H15` | output | transmit enable |
| `eth_txd[0]` | `H14` | output | transmit data bit 0 |
| `eth_txd[1]` | `J14` | output | transmit data bit 1 |
| `eth_txd[2]` | `J13` | output | transmit data bit 2 |
| `eth_txd[3]` | `H17` | output | transmit data bit 3 |

Use `LVCMOS33` as specified by Digilent. Add explicit generated-clock and MII
input/output timing constraints; do not stop at package-pin assignments.

## Recommended architecture

Keep the implementation as small modules with one responsibility each:

| Module | Responsibility |
|---|---|
| `ethernet_ref_clock.sv` | generate a forwarded 25 MHz clock from 100 MHz |
| `phy_reset.sv` | hold reset low, release it, and wait for PHY startup |
| `mdio_master.sv` | one Clause 22 read or write transaction |
| `phy_bringup.sv` | read identity/status and expose link/speed/duplex |
| `mii_tx.sv` | turn frame bytes into MII nibbles in the TX clock domain |
| `mii_rx.sv` | turn MII nibbles into frame bytes in the RX clock domain |
| `ethernet_fcs.sv` | Ethernet CRC-32 generation and checking |
| `ethernet_frame_tx.sv` | preamble, addresses, type, payload, padding, FCS |
| `ethernet_frame_rx.sv` | validate and describe received frames |
| `arp_responder.sv` | answer ARP requests for one fixed IPv4 address |
| `udp_echo.sv` | receive and return one fixed UDP payload format |
| `m4_uart_reporter.sv` | one compact, fixed-width status line |
| `arty_m4_ethernet_top.sv` | clocks, CDC, controls, LEDs, and module wiring |

Use asynchronous FIFOs at the RX-clock-to-system and
system-to-TX-clock boundaries. Do not sample multi-bit MII data using ordinary
two-flop synchronizers.

Use the existing `uart_tx.sv`, debouncers, reset synchronizer, CRC conventions,
simulation scripts, and Python command-line style where they fit. Do not copy
the camera-specific top and rename signals; extract only the small reusable
pieces.

## Bring-up phases

### Phase 1: reference clock, reset, and MDIO

Implement and simulate the 25 MHz forwarded clock, conservative PHY reset
delay, and Clause 22 MDIO transactions. Read PHY address 1:

| Address | Register | First use |
|---:|---|---|
| `0x00` | BMCR | reset and auto-negotiation control |
| `0x01` | BMSR | link and auto-negotiation capability/status |
| `0x02` | PHYIDR1 | expect TI identifier high word `0x2000` |
| `0x03` | PHYIDR2 | expect DP83848 identifier `0x5C90` ignoring revision bits if needed |
| `0x10` | PHYSTS | link, speed, and duplex in one read |

Read BMSR twice when checking current link state because some status bits are
latched low. Do not infer link only from the RJ-45 LEDs.

Acceptance:

- MDIO reads do not return all zeroes or all ones;
- identity matches the DP83848 family;
- UART reports link down with the cable absent and link up after negotiation;
- negotiated speed and duplex agree with the connected host or switch.

### Phase 2: MII transmit

Transmit a deterministic broadcast Ethernet frame with an experimental local
EtherType and a payload containing:

```text
M4TEST | sequence | payload length | payload pattern | payload CRC-32
```

The host script should capture raw frames, validate the destination/source
addresses, EtherType, sequence, length, pattern, and payload CRC, then print a
single PASS/FAIL summary. Start with one frame per button press before adding a
continuous mode.

Acceptance:

- Wireshark or the host script sees the exact frame;
- Ethernet FCS is accepted by the host interface;
- sequence and payload CRC match;
- repeated frames do not underrun the MII transmitter.

### Phase 3: MII receive

Have the host send the same deterministic local frame to the FPGA. The receive
path should strip the preamble/FCS, validate the frame, and report counters
over UART.

Acceptance:

- exact byte length and sequence are recovered;
- bad-FCS, `RXERR`, runt, oversize, FIFO overflow, and sequence-gap counters
  are separately visible;
- a deliberately corrupted simulation frame increments only the expected
  error counter.

### Phase 4: fixed ARP and UDP echo

Use compile-time constants first:

```text
FPGA MAC: 02:00:00:00:00:01
FPGA IPv4: 192.168.10.2
Host IPv4: 192.168.10.1
UDP port: 4000
```

Implement ARP reply and a UDP echo/test endpoint. IPv4 header checksum and UDP
length must be checked. UDP checksum may initially be transmitted as zero for
IPv4, but the choice must be explicit and tested.

Acceptance:

- the host resolves the FPGA's fixed IP with ARP;
- the host sends a numbered UDP payload and receives the exact echo;
- a sustained test reports zero missing, duplicate, corrupted, or reordered
  packets.

### Phase 5: implementation and physical evidence

Archive:

- all self-checking simulation transcripts;
- timing, utilization, CDC, and DRC reports;
- final bitstream SHA-256;
- UART link/packet status;
- host test output;
- a short packet capture containing ARP and UDP traffic.

## UART contract

Keep one fixed-width line that is useful even before UDP exists. A suitable
shape is:

```text
[PASS:PASS] M4 PHY=2000:5C90 LINK=1 SPD=100 DUP=F TX=00000064 RX=00000064 BAD=00000000 DROP=00000000 ERR=0000
```

Report fields independently:

- `PHY`: identifier registers;
- `LINK`, `SPD`, `DUP`: current negotiated state;
- `TX`, `RX`: completed valid frames;
- `BAD`: frames rejected for FCS/length/protocol reasons;
- `DROP`: FIFO overflow, underrun, or sequence loss;
- `ERR`: sticky summary bits.

As Milestone 3 demonstrated, the raw counters must remain available even when
the summary says FAIL.

## Suggested controls

- `BTN0`: reset the complete design.
- `BTN1`: restart PHY reset and MDIO discovery.
- `BTN2`: clear sticky packet errors and counters.
- `BTN3`: transmit one deterministic test frame and request UART status.
- `SW0`: continuous transmit enable.
- `SW1`: PHY internal-loopback test enable during early bring-up.
- `SW2`: select raw Ethernet test or UDP echo stage.
- `SW3`: freeze UART snapshot.
- `LD4`: heartbeat; `LD5`: PHY identity/link passed; `LD6`: packet activity;
  `LD7`: live or sticky error.

The exact switch meanings may change once implementation starts, but document
one stable mapping before physical testing.

## Required tests

At minimum, add self-checking tests for:

- 25 MHz reference clock and reset sequencing;
- MDIO read, write, turnaround, missing-PHY response, and timeout;
- PHY bring-up with link down, 100/full, and 10/half status models;
- MII low/high nibble order and byte reconstruction;
- minimum frame padding and maximum supported frame length;
- Ethernet FCS known vectors and deliberate corruption;
- RX error, runt, oversize, FIFO overflow, and TX underrun;
- consecutive frames and inter-packet gap;
- ARP request/reply;
- IPv4 checksum and malformed header rejection;
- UDP echo, bad length, sequence gap, and sustained packet stream;
- top-level UART formatting and sticky-error clearing.

## Expected files

```text
constraints/arty_a7_ethernet.xdc
rtl/ethernet/ethernet_ref_clock.sv
rtl/ethernet/phy_reset.sv
rtl/ethernet/mdio_master.sv
rtl/ethernet/phy_bringup.sv
rtl/ethernet/mii_tx.sv
rtl/ethernet/mii_rx.sv
rtl/ethernet/ethernet_fcs.sv
rtl/ethernet/ethernet_frame_tx.sv
rtl/ethernet/ethernet_frame_rx.sv
rtl/ethernet/arp_responder.sv
rtl/ethernet/udp_echo.sv
rtl/debug/m4_uart_reporter.sv
rtl/top/arty_m4_ethernet_top.sv
sim/models/dp83848_mii_model.sv
sim/tb/tb_mdio_master.sv
sim/tb/tb_mii_tx_rx.sv
sim/tb/tb_ethernet_frames.sv
sim/tb/tb_arp_udp.sv
sim/tb/tb_arty_m4_ethernet_top.sv
scripts/run_m4_simulations.tcl
scripts/check_m4_synthesis.tcl
scripts/build_m4_bitstream.tcl
scripts/python/ethernet_test.py
docs/milestone4_ethernet_logic_walkthrough.md
docs/milestone4_ethernet_hardware_validation.md
docs/milestone4_simulation_results.txt
```

## Deliberately outside Milestone 4

- camera pixels entering the Ethernet packetizer;
- live frame reconstruction on the host;
- DHCP, DNS, TCP, HTTP, or a general-purpose network stack;
- MicroBlaze, an operating system, or vendor Ethernet IP unless the project
  explicitly changes direction;
- DDR frame buffering;
- Gigabit Ethernet.

These belong to later integration or are unnecessary for proving the 10/100
transport. The first Milestone 4 implementation step should be the 25 MHz
clock, reset sequencer, and one readable MDIO register—not UDP and not camera data.
