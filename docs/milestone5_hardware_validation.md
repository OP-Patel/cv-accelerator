# Milestone 5 hardware validation

## Current status

The integrated RTL, host receiver, self-checking simulations, synthesis,
placement, routing, timing, and bitstream generation are complete. Physical
camera-over-Ethernet acceptance has not yet been run, so Milestone 5 must not
yet be described as physically complete.

Verified implementation results from July 18, 2026:

| Check | Result |
|---|---|
| Four M5 XSim targets | PASS |
| Routed setup timing | WNS 0.634 ns, TNS 0 |
| Routed hold timing | WHS 0.036 ns, THS 0 |
| Slice LUTs | 11,721 / 63,400 (18.49%) |
| Slice registers | 25,524 / 126,800 (20.13%) |
| Block RAM tiles | 14 / 135 (10.37%) |
| Bitstream SHA-256 | `8c9577a1ff240642bf1aef7a37178feb910d6b0b2e218a7052d94dc535e7bc00` |

The routed DRC has no errors, but contains 30 RAMB async-control warnings from
the asynchronous FIFO implementations plus one report-limit warning. The CDC
report still flags the inferred M4 TX async FIFO, asynchronous reset
qualification, XPM Gray-pointer buses, the coherent snapshot bus, and a camera
diagnostic flag. These findings are archived in `drc_milestone5.rpt` and
`cdc_milestone5.rpt`; physical acceptance does not waive them.

## Bitstream and host command

Generated bitstream:

```text
vivado_project_m5/arty_conv_m5.runs/impl_1/arty_m5_camera_ethernet_top.bit
```

Configure the host adapter as `192.168.10.1/24`, with the FPGA at
`192.168.10.2`. After programming the board, first repeat M4 ARP and UDP echo
on port 4000. Then run from the repository root:

```text
python scripts/python/camera_udp_receiver.py --frames 1 --stream sobel
python scripts/python/camera_udp_receiver.py --frames 100 --stream sobel
python scripts/python/camera_udp_receiver.py --frames 300 --stream sobel
```

For deterministic bring-up, set `SW0=1`, restart the camera with `BTN1`, and
set `SW2=1`. The one-frame run must produce a 318x238 PGM from exactly 74
packets and 75,684 image bytes. Repeat with `--stream gray` to exercise the
320x240 diagnostic mode.

## Physical acceptance still required

- confirm camera identity/configuration and 100 Mb/s full-duplex link
- confirm M4 ARP and UDP echo remain functional in the integrated bitstream
- reconstruct one color-bar Sobel frame with zero host integrity counters
- reconstruct 100 consecutive color-bar frames without drops or errors
- reconstruct at least 300 live frames at 318x238
- finish with host missing/duplicate/reordered/malformed/CRC counters at zero
- finish with FPGA camera, FIFO, Ethernet, packet, and combined errors at zero
- archive the PGM, UART transcript, host transcript, and short packet capture
