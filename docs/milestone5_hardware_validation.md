# Milestone 5 hardware validation

## Current status

**PASS — accepted as physically complete on July 18, 2026.**

The integrated RTL, host receiver, self-checking simulations, synthesis,
placement, routing, timing, bitstream generation, camera-over-Ethernet path,
and preserved M4 UDP echo path have all operated successfully on the physical
Arty A7-100T.

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
| Physical Sobel archive | 216 consecutive frames, sequence 0 through 215 |
| Reconstructed image | 318x238, 75,684 pixels, valid binary PGM |
| Integrated M4 UDP echo | PASS, confirmed by the user |

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

## Physical result

The host created `frame_00000000.pgm` through `frame_00000215.pgm` without a
sequence gap. All 216 files are exactly 75,699 bytes: a 15-byte
`P5\n318 238\n255\n` header followed by the expected 75,684 Sobel pixels. The
receiver writes a PGM only after assembling every packet and validating the
M5 header, payload length, packet placement, and payload CRC-32.

The user also confirmed that the preserved M4 UDP echo behavior passes while
running the integrated M5 bitstream. This proves that camera streaming did not
replace or break the established port-4000 path.

The original plan proposed 300 frames. The retained local archive contains
216 consecutive validated frames; the user accepted this physical run as the
Milestone 5 pass. Generated PGM files remain local under `docs/m5_frames/` and
are excluded from version control; the concise evidence is retained here and
in `milestone5_hardware_results.txt`.

## Non-blocking follow-up

- archive a final UART status line and packet capture if durable raw evidence is desired
- extend a future characterization run to 300 or more frames
- close or formally waive the remaining vendor CDC/DRC warnings
