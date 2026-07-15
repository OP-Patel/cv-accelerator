# Milestone 3 camera hardware validation

Status: **not yet physically validated**.

The photographed connector, Arty A7 pin assignment, RTL, all eight XSim tests,
implemented timing, and bitstream are complete. The remaining work begins with
physically wiring the unbranded module and checking it on the bench.

## Before connecting the module

- [x] Record front and back photographs of the module.
- [ ] Identify the manufacturer/part number or find an authoritative schematic.
- [x] Verify that the module power input is labelled `3.3V`.
- [ ] Measure its current and confirm the sensor-side I/O rail.
- [ ] Verify DVP, SCCB, reset, power-down, and XCLK voltage compatibility with Arty A7 I/O.
- [ ] Verify SCCB pull-ups and their rail.
- [x] Verify connector orientation and every printed signal label from the photos.
- [x] Verify the FPGA package pins against Digilent's Arty A7 Master XDC.
- [x] Create, review, implement, and route `constraints/arty_a7_camera.xdc`.

The board has regulator-looking components but no visible multi-channel level
translator. Direct wiring is a reasonable lab bring-up for this common module
layout, but the photographs cannot prove the sensor-side I/O voltage. The XDC's
4 mA drive setting is not a voltage translator. Add level shifting on FPGA
outputs for a conservative or permanent design.

## Wiring, with both boards powered off

Use the printed camera labels rather than counting connector pins. Keep every
jumper short (about 10 cm or less) and route the camera signals as follows:

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

Connect camera `DGND` to `JB5` and camera `3.3V` to `JB6`. On an Arty Pmod,
pins 5/11 are ground and pins 6/12 are 3.3 V. Connect ground first, power
second, and signals last. Inspect for shifted connectors or adjacent shorts
before applying USB power. Remove power immediately if the module becomes hot.

With the camera lens facing you and its text upright, its two columns are:

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

## Board controls

- `BTN0`: reset the complete design.
- `BTN1`: restart camera register initialization; set `SW0` first.
- `BTN2`: clear sticky error flags.
- `BTN3`: request a UART status line.
- `SW0`: enable the camera's color bars at the next initialization.
- `SW1`: report raw grayscale instead of Sobel output.
- `SW2`: swap the two RGB565 bytes for byte-order diagnosis.
- `SW3`: freeze the last completed-frame snapshot.
- `LD4`: heartbeat; `LD5`: configuration passed; `LD6`: frame activity;
  `LD7`: any live error.

## Staged evidence to capture

- [ ] Measure 24 MHz XCLK and 45-55% duty cycle at the module.
- [x] Record the physical identity: `ID=7673` with zero NACKs on stable reads.
- [ ] Record `CFG=P`, the full configuration write count, and zero NACKs.
- [ ] Use ILA to prove active-high VSYNC/HREF and RGB565 byte order.
- [ ] Prove 640 bytes, 320 pixels per line, and 240 lines per frame.
- [ ] Prove zero FIFO drops/overflow over a sustained run.
- [x] Prove stable framing over 100+ frames: 640 raw bytes, 240 lines,
  76,800 pixels, and 75,684 Sobel outputs per frame.
- [ ] Record the sensor color-bar grayscale CRC.
- [ ] Record 76,800 camera inputs and 75,684 Sobel outputs.
- [ ] Save UART output in `docs/milestone3_uart_capture.txt`.
- [x] Save timing, utilization, CDC, DRC, and bitstream evidence.

## Build and monitor commands

From `scripts/`:

```text
vivado -mode batch -source create_project.tcl
vivado -mode batch -source run_m3_simulations.tcl
vivado -mode batch -source build_m3_bitstream.tcl
```

The final command uses the enabled camera XDC and refuses negative setup slack.

Monitor and record UART evidence with:

```text
python python/camera_status_monitor.py --list
python python/camera_status_monitor.py --port COM4 --output ../docs/milestone3_uart_capture.txt
```
