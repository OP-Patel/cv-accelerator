# Milestone 4 10/100 Ethernet logic walkthrough

## Scope and fixed network identity

This milestone implements a small hardware MAC for the Arty A7-100T's onboard
TI DP83848J. It is a 4-bit MII design for **10 or 100 Mb/s only**. It does not
contain RMII, RGMII, gigabit logic, a MicroBlaze, or a general-purpose stack.

- FPGA MAC: `02:00:00:00:00:01`
- FPGA IPv4: `192.168.10.2`
- host IPv4: `192.168.10.1/24`
- UDP port: `4000`
- experimental raw EtherType: `0x88B5`

## Clock, reset, and PHY discovery

`ethernet_ref_clock.sv` uses an Artix-7 MMCM and ODDR to forward a 25 MHz,
50-percent-duty-cycle clock on `ETH_REF_CLK`. `phy_reset.sv` holds `ETH_RSTN`
low for 10 ms and waits another 10 ms before allowing MDIO discovery.

`mdio_master.sv` implements Clause 22 reads and writes with a 32-one preamble,
open-drain MDIO, turnaround checking, and a transaction timeout.
`phy_bringup.sv` reads PHY address 1 in this order:

1. `PHYIDR1` (`0x02`), expected `0x2000`;
2. `PHYIDR2` (`0x03`), expected `0x5C9x` with revision ignored;
3. `BMCR` (`0x00`) to enable/restart auto-negotiation or loopback;
4. `BMSR` (`0x01`) twice because link is latched low;
5. `PHYSTS` (`0x10`) for live link, speed, and duplex.

The DP83848-specific speed polarity is explicit: `PHYSTS[1]=1` means 10 Mb/s
and zero means 100 Mb/s. `PHYSTS[2]` is full duplex and `PHYSTS[0]` is link.

## MII and clock-domain handling

At 100 Mb/s the PHY supplies 25 MHz TX and RX clocks. At 10 Mb/s it supplies
2.5 MHz clocks. No system-clock divider guesses the speed: the MAC follows the
clocks returned by the PHY.

`mii_tx.sv` drives the low nibble and then high nibble on TX clock rising edges;
the PHY samples them on falling edges. `mii_rx.sv` reconstructs low-nibble-first
bytes in the RX clock domain. Complete `{last, byte}` records cross to the TX
domain through a Gray-pointer asynchronous FIFO. Multi-bit MII data is never
passed through individual two-flop synchronizers.

## Ethernet, raw test, ARP, and UDP

`ethernet_frame_tx.sv` adds seven `0x55` preamble bytes, `0xD5`, minimum-frame
padding, and reflected Ethernet CRC-32/FCS. `ethernet_frame_rx.sv` locates the
SFD, bounds the frame, checks residue `0xDEBB20E3`, parses fixed headers, and
keeps separate runt, oversize, RXERR, FCS, protocol, and sequence counters.

The raw `0x88B5` payload is:

```text
M4TEST | sequence:u32-be | pattern_length:u16-be=30 |
30 pattern bytes | payload_crc32:u32-le
```

The ARP responder answers only for `192.168.10.2`. The UDP endpoint accepts
fixed-IHL IPv4 packets only when the IPv4 checksum, IP total length, UDP length,
destination address, and port are valid. Replies echo the payload exactly.
The transmitted UDP checksum is zero, which is explicitly permitted for IPv4;
Ethernet FCS and the IPv4 header checksum remain enabled.

## Controls and status

- `BTN0`: complete design reset
- `BTN1`: repeat PHY reset and MDIO discovery
- `BTN2`: clear packet counters and sticky errors
- `BTN3`: transmit one raw test frame and print status
- `SW0`: continuous raw test frames
- `SW1`: DP83848 internal loopback in forced 100/full test mode
- `SW2`, `SW3`: reserved
- `LD4`: heartbeat
- `LD5`: valid PHY identity and link
- `LD6`: packet activity
- `LD7`: error summary

UART uses 115200 8N1 and reports:

```text
[PASS:PASS] M4 PHY=2000:5C90 LINK=1 SPD=100 DUP=F TX=00000064 RX=00000064 BAD=00000000 DROP=00000000 ERR=0000
```

The first PASS is PHY discovery/identity. The second is the packet/FIFO error
summary. Raw counters remain authoritative.

## Build and regression

From `scripts/` in a Vivado command prompt:

```text
vivado -mode batch -source create_project.tcl
vivado -mode batch -source run_m4_simulations.tcl
vivado -mode batch -source check_m4_synthesis.tcl
vivado -mode batch -source build_m4_bitstream.tcl
```

The bitstream target writes timing, utilization, CDC, DRC, and SHA-256 files
under `docs/`. Physical validation passed on July 17, 2026; the repeatable
procedure, final UART counters, Wireshark filter, and remaining CDC review are
recorded in `milestone4_ethernet_hardware_validation.md`.

To inspect the implemented design or program the board in the Vivado GUI, open
the dedicated Milestone 4 project from PowerShell:

```powershell
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  "C:\Users\Om Patel\Desktop\arty-conv-accelerator\vivado_project_m4\arty_conv_m4.xpr"
```

Do not use the obsolete `vivado_project\arty_conv.xpr` path. The verified M4
bitstream is under
`vivado_project_m4/arty_conv_m4.runs/impl_1/arty_m4_ethernet_top.bit`.
