# Milestone 4 Ethernet hardware validation

Status: **functional hardware validation passed on July 17, 2026**.

The Arty A7-100T discovered its onboard DP83848J, negotiated a 100 Mb/s
full-duplex link, transmitted and received the deterministic raw Ethernet
format, answered ARP, and sustained 10,000 UDP echo exchanges. The final UART
snapshot had zero bad, dropped, or sticky-error counts.

The concise evidence is preserved in `milestone4_hardware_results.txt`. The
failure-to-fix sequence is in `milestone4_ethernet_debugging_postmortem.md`.

## Acceptance result

| Check | Expected | Final evidence | Result |
|---|---|---|---|
| PHY family | `PHYIDR1=2000`, `PHYIDR2=5C9x` | `PHY=2000:5C90` | Pass |
| Link | up | `LINK=1` | Pass |
| Negotiated mode | 100 Mb/s, full duplex | `SPD=100 DUP=F` | Pass |
| Raw FPGA transmit | exact `0x88B5` payload accepted by host | `raw-listen valid=1 bad=0 gaps=0` | Pass |
| Raw FPGA receive | at least 100 valid frames | clean run reached `RX=00000073` (115 total valid frames) | Pass |
| Raw receive errors | zero | `BAD=0 DROP=0 ERR=0` | Pass |
| ARP | reply for `192.168.10.2` | `192.168.10.2 is at 02:00:00:00:00:01` | Pass |
| UDP echo | exact reply from port 4000 | paired host-to-FPGA and FPGA-to-host 46-byte UDP payloads | Pass |
| Sustained UDP | 10,000 exchanges | final `TX=00002714` (10,004) and paired Wireshark traffic | Pass |
| Final packet status | no bad/drop/sticky error | `BAD=00000000 DROP=00000000 ERR=0000` | Pass |
| XSim regression | all five M4 targets pass | five exact `PASS:` markers | Pass |
| Routed timing | nonnegative setup and hold | WNS `1.477 ns`, WHS `0.057 ns` | Pass |
| Routed DRC | no findings | `Checks found: 0` | Pass |

`RX` counts every valid Ethernet frame, not only the experimental raw
EtherType. Windows multicast, discovery, and other background packets explain
why the clean 100-frame raw test ended at 115 rather than exactly 100.

`TX=0x2714` is 10,004 decimal. It is consistent with 10,000 UDP replies plus
ARP and manual/raw test traffic. `RX=0x2957` is 10,583 decimal and includes the
10,000 UDP requests plus valid background traffic.

## Hardware and host setup

- Board: Digilent Arty A7-100T (`xc7a100tcsg324-1`)
- PHY: onboard TI DP83848J in 4-bit MII mode, PHY address 1
- FPGA MAC: `02:00:00:00:00:01`
- FPGA IPv4: `192.168.10.2`
- FPGA UDP port: `4000`
- Host adapter: `Ethernet 2`
- Host adapter hardware: ASIX AX88179 USB 3.0 to Gigabit Ethernet Adapter
- Host adapter MAC observed in Wireshark: `9c:69:d3:39:f5:84`
- Host IPv4: `192.168.10.1/24`, no gateway, no DNS
- UART: 115200 baud, 8 data bits, no parity, one stop bit
- Packet capture: Wireshark on `Ethernet 2`

The host adapter must be configured manually. An automatic private address
such as `169.254.108.10` is not on the FPGA's fixed `192.168.10.0/24` subnet.
Open `ncpa.cpl`, select `Ethernet 2`, open IPv4 properties, and set:

```text
IP address:      192.168.10.1
Subnet mask:     255.255.255.0
Default gateway: blank
DNS:             blank
```

Scapy raw modes require Npcap and may require an elevated terminal.

## Bitstream used

Open the dedicated project from PowerShell:

```powershell
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  "C:\Users\Om Patel\Desktop\arty-conv-accelerator\vivado_project_m4\arty_conv_m4.xpr"
```

Program:

```text
vivado_project_m4/arty_conv_m4.runs/impl_1/arty_m4_ethernet_top.bit
```

SHA-256:

```text
90895b8f519ab28e7e73f63ffed21c17be36246ec6b75978ea941413b596da5e
```

## Repeatable procedure

### 1. Verify simulation and implementation

From `scripts/`:

```powershell
$env:XILINX_LOCAL_USER_DATA = "NO"
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode batch -source run_m4_simulations.tcl -notrace
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode batch -source build_m4_bitstream.tcl -notrace
```

### 2. Confirm PHY identity and link

Start the UART monitor, program the board, and wait for negotiation. A transient
`LINK=0 DUP=H` line is normal during negotiation. Do not begin traffic testing
until a fresh line reports:

```text
PHY=2000:5C90 LINK=1 SPD=100 DUP=F
```

Set `SW0=0` for one-shot raw testing. `SW0=1` continuously generates FPGA raw
frames and can obscure which action caused a counter change.

### 3. Verify FPGA-to-host raw Ethernet

Start the listener, then press `BTN3`:

```powershell
python scripts/python/ethernet_test.py raw-listen --interface "Ethernet 2" --count 1
```

Expected:

```text
PASS raw-listen valid=1 bad=0 gaps=0
```

### 4. Verify host-to-FPGA raw Ethernet

Press `BTN2` to clear counters, wait for the button to be released and
debounced, then send one sequence:

```powershell
python scripts/python/ethernet_test.py raw-send --interface "Ethernet 2" --count 100 --start 1
```

Expected host output:

```text
PASS raw-send frames=100 first=1 last=100
```

Press `BTN3` for a new UART snapshot. `RX` must increase by at least 100 and
`BAD`, `DROP`, and `ERR` must remain zero. Do not start a second batch at
sequence 1 without clearing first; use `--start 101` or clear the sequence
history with `BTN2`.

### 5. Verify ARP and one UDP echo

Start Wireshark on `Ethernet 2` and use this display filter:

```text
arp || udp.port == 4000
```

The simpler filter `udp` hides the ARP request and response.

Clear the target entry and send one packet:

```powershell
arp -d 192.168.10.2
python scripts/python/ethernet_test.py udp --count 1 --timeout 2
```

The capture must show this order:

1. host broadcast: `Who has 192.168.10.2? Tell 192.168.10.1`;
2. FPGA reply: `192.168.10.2 is at 02:00:00:00:00:01`;
3. host UDP payload to destination port 4000;
4. FPGA UDP reply from source port 4000 with the same 46-byte payload.

### 6. Run sustained UDP echo

Start with a short batch:

```powershell
python scripts/python/ethernet_test.py udp --count 100 --interval 0.001
```

Then run the acceptance batch:

```powershell
python scripts/python/ethernet_test.py udp --count 10000 --interval 0.001
```

The utility prints only its final summary. With a broken route, each missing
reply consumes the default one-second timeout, so 10,000 failures can look like
a hang for almost 2 hours 47 minutes. Always prove `--count 1` before the long
run.

After completion, press `BTN3` and archive the UART line and packet capture.

## Final UART evidence

Clean baseline:

```text
[2026-07-17 20:41:54] [PASS:PASS] M4 PHY=2000:5C90 LINK=1 SPD=100 DUP=F TX=00000000 RX=00000000 BAD=00000000 DROP=00000000 ERR=0000
```

After the raw receive test:

```text
[2026-07-17 20:42:20] [PASS:PASS] M4 PHY=2000:5C90 LINK=1 SPD=100 DUP=F TX=00000000 RX=00000073 BAD=00000000 DROP=00000000 ERR=0000
```

After sustained UDP echo:

```text
[2026-07-17 20:51:38] [PASS:PASS] M4 PHY=2000:5C90 LINK=1 SPD=100 DUP=F TX=00002714 RX=00002957 BAD=00000000 DROP=00000000 ERR=0000
```

## Implementation evidence

- Vivado 2026.1 XSim: all five Milestone 4 testbenches pass.
- Routed timing: WNS `1.477 ns`, TNS `0.000 ns`, WHS `0.057 ns`, THS `0.000 ns`.
- Routed DRC: zero findings.
- Utilization: 7,170 slice LUTs (11.31%), 14,520 slice registers (11.45%),
  one MMCM, and four BUFGs.
- Reports: `timing_summary_milestone4.rpt`, `utilization_milestone4.rpt`,
  `cdc_milestone4.rpt`, and `drc_milestone4.rpt`.

## CDC review carried into Milestone 5

The routed design passes timing and sustained hardware traffic, but
`report_cdc` is not clean. It reports custom asynchronous-FIFO RAM paths,
combinational logic before the RX/TX reset synchronizers, Gray-pointer buses,
and a wide diagnostic counter bus sampled for UART. The FIFO findings are
consistent with an inferred dual-clock FIFO that Vivado does not recognize as
an XPM primitive. The wide status bus is diagnostic only and is not used for
packet control, but it can produce a torn UART snapshot.

Milestone 5 must not extend that pattern into its data plane. Use an XPM or a
fully constrained/reviewed asynchronous FIFO for streaming data and a
request/acknowledge snapshot handshake for coherent multi-bit status.

## Remaining characterization, not a functional blocker

- A forced or negotiated 10 Mb/s physical run was not performed because no
  deliberate 10 Mb/s partner was used.
- The screenshot proved paired ARP/UDP traffic, but a `.pcapng` file is not
  present in the checkout.
- The operator confirmed successful completion of the 10,000-packet command;
  its exact final Python summary line was not copied into this record.
- CDC report findings still require explicit disposition or cleanup as part of
  the integrated Milestone 5 design.

These limitations do not change the observed functional result at 100 Mb/s
full duplex: raw TX/RX, ARP, and sustained UDP echo all operated with zero
reported packet, FIFO, or sticky errors.
