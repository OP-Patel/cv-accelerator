# Milestone 3 camera hardware validation

Status: **functional hardware validation passed on July 14, 2026**.

The Arty A7-100T configured the photographed OV7670 module, captured complete
320x240 RGB565 frames, converted every pixel to grayscale, and produced the
expected cropped Sobel stream. The final run completed 306 frames without a
reported failure.

This document records the final result and the repeatable bench procedure. The
full sequence of failures and fixes is in
`milestone3_camera_debugging_postmortem.md`. The unedited UART history is in
`milestone3_uart_capture.txt`.

## Acceptance result

| Check | Expected | Final evidence | Result |
|---|---:|---:|---|
| SCCB identity | `0x7670` or `0x7673` | `ID=7673` | Pass |
| Configuration | complete, no NACK | `CFG=P WR=0042 NACK=0000` | Pass |
| Raw active bytes per line | 640 | `RAWB=0280` | Pass |
| Raw active lines per frame | 240 | `RAWL=00F0` | Pass |
| Accepted lines | 240 | `LINE=00F0` | Pass |
| Input pixels per frame | 76,800 | `PIX=00012C00` | Pass |
| Sobel outputs per frame | 75,684 | `OUT=000127A4` | Pass |
| Grayscale CRC-32 | stable | `GRAY=B4784EF0` | Pass |
| Sobel CRC-32 | stable | `SOB=6A41EC97` | Pass |
| Sticky error flags | zero | `ERR=0000` | Pass |
| Sustained run | at least 100 frames | frames 1 through 306 | Pass |

The first completed frame reports `RAWL=0000` because the raw diagnostic
snapshot crosses from the camera clock domain independently from the completed
frame snapshot. From frame 2 onward it is consistently `RAWL=00F0`. The
accepted line, pixel, output, CRC, and error fields are already correct on
frame 1.

Representative final lines:

```text
[PASS:PASS] M3 ID=7673 CFG=P WR=0042 NACK=0000 F=00000001 LINE=00F0 PIX=00012C00 GRAY=B4784EF0 OUT=000127A4 SOB=6A41EC97 ERR=0000 RAWB=0280 RAWL=0000
[PASS:PASS] M3 ID=7673 CFG=P WR=0042 NACK=0000 F=00000002 LINE=00F0 PIX=00012C00 GRAY=B4784EF0 OUT=000127A4 SOB=6A41EC97 ERR=0000 RAWB=0280 RAWL=00F0
[PASS:PASS] M3 ID=7673 CFG=P WR=0042 NACK=0000 F=00000132 LINE=00F0 PIX=00012C00 GRAY=B4784EF0 OUT=000127A4 SOB=6A41EC97 ERR=0000 RAWB=0280 RAWL=00F0
```

`F=00000132` is hexadecimal frame 306. The final supplied capture contains no
`FAIL` line.

## Wiring used for the passing run

Use the printed camera labels rather than counting connector pins. With both
boards powered off, connect:

| Camera | Arty | Camera | Arty |
|---|---|---|---|
| `PLK` | `JB1` | `D0` | `JC1` |
| `VS` | `JB2` | `D1` | `JC2` |
| `HS` | `JB3` | `D2` | `JC3` |
| `XLK` | `JB4` | `D3` | `JC4` |
| `SCL` | `JB7` | `D4` | `JC7` |
| `SDA` | `JB8` | `D5` | `JC8` |
| `RET` | `JB9` | `D6` | `JC9` |
| `PWDN` | `JB10` | `D7` | `JC10` |

Connect camera `DGND` to `JB5` and camera `3.3V` to `JB6`. Connect ground
first, power second, and signals last. Keep the jumpers short and inspect for
shifted connections before applying power.

With the lens facing you and the printed text upright, the module header is:

```text
3.3V   DGND
SCL    SDA
VS     HS
PLK    XLK
D7     D6
D5     D4
D3     D2
D1     D0
RET    PWDN
```

## Controls

- `BTN0`: reset the complete FPGA design.
- `BTN1`: restart camera identification and register initialization.
- `BTN2`: clear sticky capture and pipeline error flags.
- `BTN3`: request an immediate UART status line.
- `SW0`: enable camera color bars on the next initialization.
- `SW1`: select raw grayscale rather than Sobel for the output checksum path.
- `SW2`: swap RGB565 bytes for byte-order diagnosis.
- `SW3`: freeze the last completed-frame UART snapshot.
- `LD4`: heartbeat; `LD5`: configuration passed; `LD6`: frame activity;
  `LD7`: any live error.

## Repeat the validation

From `scripts/` in a Vivado command prompt:

```text
vivado -mode batch -source create_project.tcl
vivado -mode batch -source run_m3_simulations.tcl
vivado -mode batch -source build_m3_bitstream.tcl
```

Program:

```text
vivado_project/arty_conv.runs/impl_1/arty_m3_camera_top.bit
```

Record the UART stream at 115200 baud, 8 data bits, no parity, and one stop
bit:

```text
python python/camera_status_monitor.py --list
python python/camera_status_monitor.py --port COM4 --output ../docs/milestone3_uart_capture.txt
```

After programming, press `BTN1` if the first automatic SCCB attempt reports a
NACK. Then press `BTN3` to request a status snapshot. A completed frame must
match the acceptance table above. Do not clear an error merely to obtain a
green line; investigate the first nonzero `ERR`, `RAWB`, and `RAWL` values.

## Implementation evidence

- Vivado 2026.1 implementation meets all specified timing constraints.
- Routed timing: WNS `0.771 ns`, TNS `0.000 ns`, WHS `0.070 ns`, THS `0.000 ns`.
- Final hardware-tested bitstream SHA-256:
  `14B3C502EEBD432A32925B8987DE62A80433516F124264DA019BAD5A3222B446`.
- Reports: `timing_summary_milestone3.rpt`,
  `utilization_milestone3.rpt`, and `cdc_milestone3.rpt`.

## Remaining characterization, not a functional blocker

The functional milestone passes, but the following facts were not established
by the UART run:

- the unbranded module's manufacturer, schematic, current consumption, and
  sensor-side I/O voltage remain unknown;
- XCLK duty cycle and PCLK timing were not measured with an oscilloscope;
- no ILA trace was archived;
- final source-synchronous input-delay constraints still require measured PCLK
  and jumper-wire skew.

These limitations matter before treating the jumper-wire prototype as a
production electrical design. They do not change the observed result that the
camera-to-Sobel data path processed 306 consecutive, complete frames without a
reported functional error.
