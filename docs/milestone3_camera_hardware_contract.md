# Milestone 3 OV7670 hardware contract

## Safe-to-use facts

| Item | Implemented value |
|---|---|
| Sensor interface | Direct 8-bit DVP; no AL422 FIFO controls |
| SCCB address | 7-bit `0x21`; wire bytes `0x42` write and `0x43` read |
| Accepted identity | `PID=0x76`, `VER=0x70` |
| Reference clock | 24 MHz from an Artix-7 MMCM and ODDR |
| SCCB clock | Approximately 100 kHz |
| Initial image mode | 320x240 RGB565, high byte first |
| Sync convention | Active-high VSYNC frame blanking and active-high HREF line data |
| Active data | 640 bytes per line, 320 pixels per line, 240 lines per frame |

The identity value deliberately follows the supplied OV7670 datasheet version 1.01. Some later sensors and the current Linux driver use `0x7673`; that is not silently accepted because it may identify a different revision.

## Register-table sources

`camera_register_init.sv` uses a short table with named groups rather than a large unexplained dump:

- QVGA scaling and clock values come from Table 2-2 of the OmniVision OV7670/OV7171 Implementation Guide version 1.0.
- RGB mode and RGB565 selection come from Tables 2-1 and 6-5 of that guide and the version-1.01 sensor datasheet.
- Gamma, AEC/AGC thresholds, and the RGB565 color matrix follow the Linux `ov7670.c` driver, which labels those groups and attributes its default values to OmniVision.
- `COM10=0x00` fixes normal HREF/VSYNC polarity instead of hiding polarity inversions in capture RTL.
- `COM17[3]` is the deterministic sensor color-bar control selected by `SW0` when initialization starts.

Primary implementation references:

- OmniVision OV7670/OV7171 Implementation Guide v1.0: <https://web.mit.edu/6.111/www/f2017/tools/OV7670app.pdf>
- Linux OV7670 driver: <https://github.com/torvalds/linux/blob/master/drivers/media/i2c/ov7670.c>
- Project-authoritative sensor document named in the plan: `OV7670_DS (1.01).fm - OV7670.pdf`, SHA-256 `C58749ACCCA5E39E950081F957EEE3DF72FC4B66B633CF168F03E87E8F202425`

## Photographed module

The supplied front and back photographs identify an unbranded, 18-pin,
no-FIFO OV7670 breakout. The board is marked for a 3.3 V supply and contains
two small regulator circuits (`U2` and `U3`) with their bypass capacitors.
There is no visible multi-channel logic-level translator. Most header signals
therefore appear to connect directly to the sensor, as on other modules with
this same layout.

With the lens facing the viewer and the connector text upright, the two header
columns read from top to bottom as follows:

| Left column | Right column |
|---|---|
| `3.3V` | `DGND` |
| `SCL` | `SDA` |
| `VS` | `HS` |
| `PLK` | `XLK` |
| `D7` | `D6` |
| `D5` | `D4` |
| `D3` | `D2` |
| `D1` | `D0` |
| `RET` | `PWDN` |

The bare OV7670 specifies a 1.7-3.0 V I/O supply. Its outputs are compatible
with an Artix-7 LVCMOS33 input when the module's I/O rail is in the usual
2.5-3.0 V range. FPGA-to-camera signals are kept at 4 mA drive strength, but
that setting limits current rather than translating voltage. Use short wires;
for a conservative product design, add proper level translation on `XLK`,
`SCL`, `RET`, `PWDN`, and the bidirectional `SDA` signal.

## Remaining electrical unknowns

The photographs settle the connector and pin map, but cannot settle the items
below. Keep these limitations visible during bench bring-up.

| Item | Required evidence |
|---|---|
| Camera module | Manufacturer and part number remain unknown; photographs are recorded above |
| Module schematic | No authoritative schematic has been found for this unbranded board |
| Module power | Input is labelled `3.3V`; measured current remains unknown |
| I/O voltage | Proof that every DVP/SCCB/control signal is safe for Arty A7 I/O, or the selected level shifters |
| SCCB pull-ups | Present/absent, resistance, and pull-up rail |
| Connector orientation | Verified from the front photograph; exact layout is recorded above |
| Package-pin map | Verified against Digilent's Arty-A7-100 Master XDC and implemented |
| Measured PCLK | Nominal and maximum period used for timing constraints |
| Input delays | Values derived from sensor timing, measured PCLK, and wiring skew |

The reviewed assignment is enabled in `constraints/arty_a7_camera.xdc`.
`constraints/arty_a7_camera.template.xdc` remains as an annotated reference.

## Implemented Arty A7 wiring

This assignment uses both high-speed Pmod headers and puts `PLK` on the
clock-capable `JB1` input. It is enabled in
`constraints/arty_a7_camera.xdc`.

| Camera label | Arty header | FPGA package pin | RTL port |
|---|---:|---:|---|
| `PLK` | `JB1` | `E15` | `cam_pclk` |
| `VS` | `JB2` | `E16` | `cam_vsync` |
| `HS` | `JB3` | `D15` | `cam_href` |
| `XLK` | `JB4` | `C15` | `cam_xclk` |
| `SCL` | `JB7` | `J17` | `cam_sio_c` |
| `SDA` | `JB8` | `J18` | `cam_sio_d` |
| `RET` | `JB9` | `K15` | `cam_reset_n` |
| `PWDN` | `JB10` | `J15` | `cam_pwdn` |
| `D0` | `JC1` | `U12` | `cam_d[0]` |
| `D1` | `JC2` | `V12` | `cam_d[1]` |
| `D2` | `JC3` | `V10` | `cam_d[2]` |
| `D3` | `JC4` | `V11` | `cam_d[3]` |
| `D4` | `JC7` | `U14` | `cam_d[4]` |
| `D5` | `JC8` | `V14` | `cam_d[5]` |
| `D6` | `JC9` | `T13` | `cam_d[6]` |
| `D7` | `JC10` | `U13` | `cam_d[7]` |

Pmod pins 5 and 11 are ground. Pins 6 and 12 are 3.3 V. The bench wiring uses
`JB5` for `DGND` and `JB6` for the camera's labelled `3.3V` input. Connect with
both boards unpowered, use short jumpers, and inspect for shorts before power.

The header assignment and camera-side physical orientation are complete. Still
follow the printed labels rather than assuming a numbered connector end.

## Module-label normalization

| Breakout label | RTL port | Direction at FPGA |
|---|---|---|
| `PLK` | `cam_pclk` | input |
| `VS` | `cam_vsync` | input |
| `HS` | `cam_href` | input |
| `D0`...`D7` | `cam_d[0]`...`cam_d[7]` | input |
| `XLK` | `cam_xclk` | output |
| `RET` | `cam_reset_n` | output, presumed active low |
| `PWDN` | `cam_pwdn` | output |
| `SCL` | `cam_sio_c` | output |
| `SDA` | `cam_sio_d` | bidirectional open drain |

Confirm `PLK`, `XLK`, and `RET` against the actual printed module before wiring.
