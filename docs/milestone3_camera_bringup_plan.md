# Milestone 3 camera bring-up plan

## Executive summary

Milestone 3 will connect an **OV7670** parallel camera to the Arty A7 and convert its pixel timing into the raster stream already accepted by the Milestone 2 Sobel core. The initial target is 320x240 RGB565 from the sensor's 8-bit DVP interface using `PCLK`, `VSYNC`, `HREF`, `D[7:0]`, and the SCCB configuration port.

The available module is a **no-FIFO OV7670 direct-DVP breakout**. Its reported pins are `3.3V`, `DGND`, `SCL`, `SDA`, `VS`, `HS`, `PLK`, `XLK`, `D[7:0]`, `RET`, and `PWDN`. It has no AL422 read/write control pins, so the direct-DVP capture architecture in this plan is the correct starting point.

The milestone is deliberately staged. First prove safe electrical connectivity and camera configuration. Then prove byte ordering, frame timing, pixel counts, and clock-domain crossing without the Sobel pipeline. Only after the raw camera stream is trustworthy should RGB565-to-grayscale conversion and the existing convolution core be connected.

Camera pixels must not be sent one-by-one over UART. UART remains a compact status, counter, checksum, and error-reporting channel. This keeps camera frame rate independent of UART baud rate and leaves full image transport for the later Ethernet milestone.

---

## 1. Starting point from Milestone 2

Milestone 2 is physically complete and provides the following verified foundation:

- the Arty A7 clock, reset, debounced controls, heartbeat, LEDs, UART, constraints, Vivado project generation, simulation, and bitstream scripts work;
- the streaming core accepts one valid grayscale pixel per clock using `in_valid`, `in_x`, `in_y`, and `in_gray`;
- legal horizontal and vertical blanking gaps do not advance image state;
- a 320x240 input creates exactly 75,684 cropped Sobel outputs;
- the RGB565-to-grayscale conversion is already implemented and separately tested;
- two line buffers infer as `RAMB18E1` block RAMs;
- complete 320x240 XSim regression passes bit-exactly;
- implementation meets 100 MHz timing with WNS 2.284 ns and WHS 0.093 ns;
- all built-in hardware patterns reported the expected count and CRC over COM4.

The recorded Milestone 2 hardware lines are:

```text
M2 PAT=0 IN=00012C00 OUT=000127A4 CRC=CB78A10B PASS
M2 PAT=1 IN=00012C00 OUT=000127A4 CRC=CB78A10B PASS
M2 PAT=2 IN=00012C00 OUT=000127A4 CRC=18C9D29E PASS
M2 PAT=3 IN=00012C00 OUT=000127A4 CRC=01A15B08 PASS
M2 PAT=4 IN=00012C00 OUT=000127A4 CRC=0D9DA21C PASS
M2 PAT=5 IN=00012C00 OUT=000127A4 CRC=E09929FA PASS
M2 PAT=6 IN=00012C00 OUT=000127A4 CRC=E09929FA PASS
M2 PAT=7 IN=00012C00 OUT=000127A4 CRC=E09929FA PASS
```

Milestone 3 therefore does not need to redesign convolution arithmetic. Its job is to make the camera produce the proven stream contract reliably.

---

## 2. Scope and objective

Build and verify an OV7670 front end that:

1. safely powers and clocks the exact OV7670 breakout module;
2. reads the OV7670 identity registers and configures a documented 320x240 RGB565 mode;
3. captures its parallel byte stream in the camera pixel-clock domain;
4. assembles two bytes into each RGB565 pixel with confirmed byte order;
5. creates correct raster coordinates and frame/line metadata;
6. crosses into the 100 MHz system-clock domain without losing or duplicating pixels;
7. feeds the existing RGB565-to-grayscale and Sobel pipeline;
8. reports configuration state, frame counts, pixel counts, errors, and checksums over UART;
9. passes simulation, implementation, ILA inspection, and physical camera tests.

### Explicitly outside Milestone 3

- Ethernet packetization or image transfer;
- DDR or full-frame buffering;
- MicroBlaze or an operating system;
- JPEG capture or decompression;
- autofocus, auto-exposure tuning beyond a stable first configuration, or image-quality tuning;
- changing resolution while a frame is active;
- sending full 320x240 frames over UART;
- supporting several unrelated camera models in one design;
- full-resolution VGA capture in the first hardware test;
- an AL422 FIFO controller; the available module exposes the sensor bus directly and has no FIFO control pins.

The OV7670 and one stable format should be brought up thoroughly before generalizing the design.

---

## 3. OV7670 facts and Phase 0 hardware gate

The sensor is fixed as the OV7670 and the reported connector confirms a direct-DVP, no-FIFO module. The module manufacturer/part number, onboard voltage circuitry, and final camera-to-Arty package-pin mapping are still unknown. Those details must be recorded before writing final pin constraints or applying power.

### Verified OV7670 sensor facts

The following values come from the user-supplied `OV7670_DS (1.01).fm - OV7670.pdf`, OmniVision preliminary datasheet version 1.01 dated July 8, 2005. This is the project-authoritative sensor datasheet. It describes the bare sensor; a breakout may add regulators, pull-ups, oscillators, buffers, or level shifting.

| Item | OV7670 value used by this plan |
|---|---|
| Active image | VGA 640x480; QVGA 320x240 is produced by the sensor's scaling path |
| Initial output | RGB565, two successive 8-bit transfers per pixel |
| Maximum VGA rate | 30 frames/s |
| External clock | 10-48 MHz permitted, 24 MHz typical, 45-55% duty cycle |
| SCCB identity | 7-bit address `0x21`; wire bytes `0x42` for write and `0x43` for read |
| Product ID | `PID` register `0x0A` = `0x76` |
| Version ID | `VER` register `0x0B` = `0x70` |
| Manufacturer ID | `MIDH` `0x1C` = `0x7F`; `MIDL` `0x1D` = `0xA2` |
| SCCB clock | Up to 400 kHz; use approximately 100 kHz for initial bring-up |
| Parallel timing | Data is updated after the falling edge of `PCLK`; capture on its rising edge |
| Bare-sensor rails | Core 1.8 V, analog 2.45-3.0 V, I/O 1.7-3.0 V |
| Sensor order code | `OV07670-VL2A`, color, lead-free, 24-pin CSP2 |

The implementation should report `PID` and `VER` separately and expect the combined identity `0x7670`. Do not use `0x7673` from later OV7670 documentation as the acceptance value for this project unless the physical sensor is later proven to be a different revision than the supplied datasheet.

Add a completed table near the top of the eventual hardware-validation document:

| Item | Required value |
|---|---|
| Sensor | OmniVision OV7670; version 1.01 lists color order code `OV07670-VL2A` |
| Camera breakout/module | Direct-DVP OV7670 module; record manufacturer/part number if available |
| Onboard FIFO | None indicated; no AL422 control pins are exposed |
| Module schematic | Local filename or authoritative link |
| Sensor datasheet | `OV7670_DS (1.01).fm - OV7670.pdf`, version 1.01, July 8, 2005, SHA-256 `C58749ACCCA5E39E950081F957EEE3DF72FC4B66B633CF168F03E87E8F202425` |
| Interface | 8-bit parallel DVP with `PCLK`, `VSYNC`, and `HREF` |
| Initial format | RGB565 |
| Initial resolution | 320x240 |
| XCLK requirement | Start at 24 MHz; verify 45-55% duty cycle at the module pin |
| Pixel clock | Expected nominal and maximum frequency |
| I/O voltage | Confirmed compatible with Arty A7 3.3 V I/O, or level shifted |
| Power rails | Exact voltage/current and whether the module includes regulators |
| Connector mapping | Every camera signal to an FPGA package pin |
| SCCB address | 7-bit `0x21`; wire-byte notation `0x42` write / `0x43` read |
| Chip-ID registers | `0x0A=0x76`, `0x0B=0x70`; optionally verify `0x1C=0x7F`, `0x1D=0xA2` |
| RGB565 byte order | Confirm normal order versus `COM3[6]` byte swap |
| Sync polarity | Active level and timing for `VSYNC` and `HREF` |

### Reported module connector

The silkscreen names should be normalized at the FPGA wrapper as follows:

| Module label | OV7670 function | Direction at FPGA |
|---|---|---|
| `3.3V` | Module supply input | Power |
| `DGND` | Digital ground | Ground |
| `SCL` | `SIO_C`, SCCB clock | FPGA output |
| `SDA` | `SIO_D`, SCCB data | Bidirectional open-drain |
| `VS` | `VSYNC` | FPGA input |
| `HS` | `HREF` | FPGA input |
| `PLK` | Presumed `PCLK` | FPGA input |
| `XLK` | Presumed `XCLK` | FPGA output |
| `D7` through `D0` | Parallel camera data | FPGA inputs |
| `RET` | Presumed active-low `RESET` | FPGA output |
| `PWDN` | Power-down control | FPGA output |

Confirm the `PLK`, `XLK`, and `RET` abbreviations against the printed board before wiring. The data pins being printed in the order `D5, D7, D3, D1, D6, D4, D2, D0` does not change their bit numbers; constrain each label individually rather than treating their physical order as a numeric bus sequence.

### Electrical safety rules

- Do not assume a bare sensor accepts 3.3 V I/O because a breakout board is powered from 3.3 V.
- Confirm whether the module contains voltage regulators and level shifters.
- Confirm all grounds are common before connecting clocks or data.
- Do not drive a camera output signal from the FPGA.
- Confirm `PWDN`, `RESET`, SCCB, and XCLK directions from the module schematic.
- Determine whether the SCCB pull-ups are already on the module and which rail supplies them.
- Do not connect a bare OV7670 sensor directly to 3.3 V FPGA I/O; its documented I/O rail is at most 3.0 V.
- The absence of AL422 control pins confirms direct sensor capture, so `PCLK`, `HREF`, `VSYNC`, and `D[7:0]` connect to the FPGA capture logic.
- If the module uses 1.8 V or 2.8 V logic without level shifting, add proper bidirectional/unidirectional level conversion before connecting it to the Arty A7.
- Keep ribbon/jumper connections short and provide solid ground returns; a marginal `PCLK` or data bus can resemble an RTL bug.

### Recommended first interface

Use uncompressed RGB565 over the OV7670's 8-bit DVP bus. This matches the existing grayscale converter and requires two active data transfers per pixel. Do not begin with YUV or raw Bayer data.

---

## 4. OV7670-facing signals

Use names that map directly to the OV7670 datasheet while retaining the project's `cam_` prefix:

```systemverilog
input  logic       cam_pclk;
input  logic       cam_vsync;
input  logic       cam_href;
input  logic [7:0] cam_d;
output logic       cam_xclk;
output logic       cam_reset_n;
output logic       cam_pwdn;
inout  wire        cam_sio_d;
output logic       cam_sio_c;
```

These correspond to OV7670 `PCLK`, `VSYNC`, `HREF`, `D[7:0]`, `XCLK`, `RESET`, `PWDN`, `SIO_D`, and `SIO_C`. Adapt only the board-level wrapper if the breakout silkscreen uses aliases such as `SDA` and `SCL`.

### Clock roles

- `cam_xclk` is generated by the FPGA and drives the camera reference clock.
- `cam_pclk` is generated by the camera and clocks camera output data.
- The existing `clk_100mhz` remains the system, Sobel, UART, and control clock.
- `cam_pclk` and `clk_100mhz` are asynchronous clock domains even if both ultimately derive from an FPGA-generated reference.

`cam_pclk` must be declared as a real clock in the camera XDC. The OV7670 documentation specifies 15 ns data setup and 8 ns data hold around the sampling edge, with data becoming valid after the falling edge of `PCLK`. Start by sampling on the rising edge. Derive the final input-delay constraints from those values, the measured `PCLK`, and estimated board skew; do not paste generic camera constraints.

---

## 5. Recommended RTL structure

```text
rtl/camera/
  camera_xclk.sv
  sccb_master.sv
  camera_register_init.sv
  dvp_rgb565_capture.sv
  camera_stream_cdc.sv
  camera_stream_adapter.sv
  camera_debug_counters.sv

rtl/debug/
  m3_uart_reporter.sv

rtl/top/
  arty_m3_camera_top.sv

sim/tb/
  tb_camera_xclk.sv
  tb_sccb_master.sv
  tb_camera_register_init.sv
  tb_dvp_rgb565_capture.sv
  tb_camera_stream_cdc.sv
  tb_camera_stream_adapter.sv
  tb_arty_m3_camera_top.sv

sim/models/
  dvp_camera_model.sv

constraints/
  arty_a7_camera.xdc

scripts/python/
  camera_status_monitor.py
  camera_test_pattern_model.py
```

Use a separate `arty_a7_camera.xdc` rather than mixing provisional camera pins into the validated Milestone 1/2 constraint file. The Vivado project script should include both files for the Milestone 3 top.

Keep the implementation basic and readable: one clear responsibility per module, ordinary counters and finite-state machines, named constants instead of unexplained literals, and no abstraction added only to support hypothetical future cameras. Put a short purpose comment immediately before every RTL function definition. Do the same before every testbench function and task definition so stimulus and checking helpers are easy to follow.

### 5.1 `camera_xclk.sv`

Generate a 24 MHz OV7670 reference clock from the 100 MHz board clock.

- Use a Clocking Wizard/MMCM because 100 MHz cannot be divided to exactly 24 MHz with a simple integer counter.
- Keep the generated clock within the documented 10-48 MHz range and verify its 45-55% duty cycle.
- Drive the external clock using the appropriate clock-output structure recommended by Vivado, not a large combinational divider tree.
- Hold the camera in reset or power-down until XCLK has been stable for the documented startup interval.

The initial XCLK target must be a clearly named 24 MHz constant. Record the generated and measured frequency in UART status and hardware notes. Do not increase the sensor clock or frame rate until the initial configuration runs without capture or FIFO errors.

### 5.2 `sccb_master.sv`

Implement only the transactions required by the OV7670:

- start and stop conditions;
- one device address: 7-bit `0x21` internally;
- register-address write;
- register-data write;
- register read for chip ID if supported;
- ACK/NACK detection;
- clock divider for approximately 100 kHz initialization;
- timeout and sticky error output.

Keep the bus controller independent from the sensor register list. Open-drain behavior must release `SIO_D` for a logic high rather than actively driving it high. Comments must make the address notation explicit: the equivalent 8-bit SCCB address bytes are `0x42` for write and `0x43` for read. Use about 100 kHz initially, safely below the OV7670's 400 kHz maximum.

### 5.3 `camera_register_init.sv`

Store the OV7670 initialization sequence in a small ROM/table. Each entry should contain a register address and value, with an explicit end marker and optional delay marker.

The controller should expose:

```systemverilog
output logic init_busy;
output logic init_done;
output logic init_error;
output logic [15:0] completed_writes;
output logic [15:0] nack_count;
```

Keep comments beside register groups, not every individual number. Apply and verify the sequence in this order:

1. write `COM7` (`0x12`) bit 7 to reset the register set, then wait at least the documented 1 ms reset interval;
2. read `PID` (`0x0A`) and `VER` (`0x0B`) and expect `0x76` and `0x70` from the supplied version-1.01 datasheet;
3. configure the clock/prescaler and QVGA scaling registers from a documented OV7670 table;
4. select RGB output using `COM7`, then select RGB565 using `COM15` (`0x40`), with RGB444 disabled;
5. set `COM10` (`0x15`) deliberately for `PCLK`, `HREF`, and `VSYNC` behavior rather than compensating for unexplained polarity in capture RTL;
6. provide a deterministic color-bar configuration using the documented test-pattern controls;
7. enable the chosen AEC, AGC, and AWB behavior only after the deterministic path works.

Useful register landmarks are `CLKRC` `0x11`, `COM3` `0x0C`, `COM14` `0x3E`, scaling registers `0x70`-`0x73` and `0xA2`, `COM15` `0x40`, and `COM17` `0x42`. `COM3[6]` swaps output byte order. The supplied datasheet documents both `COM17[3]` and `COM7[1]` as color-bar controls; `SCALING_XSC[7]` and `SCALING_YSC[7]` provide additional test-pattern selection.

After changing the register configuration, allow the documented settling interval of up to 300 ms, or ten frames, before judging the resulting stream or checksum.

Do not present the short landmark list above as a complete initialization table. QVGA RGB565 needs a sourced, known-good OV7670 register sequence. The implementation guide's example scaling table is for processed Bayer output, so its values must not be transplanted unchanged into RGB565 mode. Record the source and purpose of every register group.

### 5.4 `dvp_rgb565_capture.sv`

This module runs entirely on `cam_pclk` and converts camera bus activity into complete RGB565 pixels.

Recommended behavior:

1. Detect the start and end of a frame from `VSYNC` using the configured `COM10` polarity.
2. Accept bytes only while the active-line signal (`HREF`) is asserted.
3. On the rising edge of `PCLK`, capture the byte that the OV7670 updated after the preceding falling edge.
4. In normal RGB565 ordering, assemble the first byte as `R[4:0]` plus `G[5:3]` and the second as `G[2:0]` plus `B[4:0]`.
5. Track the programmed `COM3[6]` byte-swap setting. A temporary named override is acceptable for diagnosis, but the normal build must agree with the register table.
6. Increment `x` only after a complete 16-bit pixel is assembled.
7. Increment `y` at the end of an active line, not from a guessed byte count.
8. Clear the half-pixel state at every line and frame boundary.
9. Flag odd byte counts, short/long lines, unexpected sync transitions, and out-of-range coordinates.

Recommended output in the camera clock domain:

```systemverilog
output logic        pixel_valid;
output logic [8:0]  pixel_x;
output logic [7:0]  pixel_y;
output logic [15:0] pixel_rgb565;
output logic        frame_start;
output logic        frame_end;
output logic        line_end;
output logic        capture_error;
```

For 320x240 RGB565, a correct frame contains 153,600 active camera bytes and 76,800 assembled pixels.

### 5.5 `camera_stream_cdc.sv`

Cross complete pixel records from `cam_pclk` into `clk_100mhz` through a small asynchronous FIFO.

Prefer a thin, well-commented wrapper around Vivado `xpm_fifo_async` over a handwritten Gray-code FIFO. Clock-domain crossing is not a useful place to save a primitive or create custom complexity.

FIFO payload should include everything needed to preserve alignment, for example:

```text
{frame_start, frame_end, line_end, x, y, rgb565}
```

Requirements:

- write only when a complete camera pixel is valid;
- read whenever the FIFO is nonempty and the downstream adapter can accept data;
- expose overflow, underflow, maximum occupancy, and dropped-pixel counters;
- make overflow sticky until reset or an explicit status clear;
- synchronize resets independently into both clock domains;
- never synchronize the multi-bit pixel bus one flip-flop at a time.

At a typical camera pixel clock below 100 MHz, the system side should drain the FIFO faster than it fills. The FIFO still matters because the domains have unrelated phase and the camera cannot be paused.

### 5.6 `camera_stream_adapter.sv`

Convert the FIFO output into the already-proven Milestone 2 stream:

```systemverilog
output logic       in_valid;
output logic [8:0] in_x;
output logic [7:0] in_y;
output logic [7:0] in_gray;
```

Instantiate `grayscale_rgb565.sv` and delay coordinates/valid by the same conversion latency. Reject or flag coordinates outside 320x240.

The adapter should also support a debug bypass that sends camera grayscale to counters/checksum without enabling Sobel. This makes it possible to distinguish a camera problem from a convolution-integration problem.

### 5.7 `camera_debug_counters.sv`

Maintain counters that can be snapshotted at frame end:

- camera bytes received;
- complete RGB565 pixels assembled;
- active lines observed;
- last line length;
- minimum and maximum line length;
- frames started and completed;
- FIFO overflow/underflow events;
- malformed/odd-byte lines;
- coordinate/protocol errors;
- raw RGB565 or grayscale CRC-32;
- Sobel output pixels and CRC-32.

Frame-end values must be snapshotted so UART can report a stable completed frame while the next frame begins.

---

## 6. Top-level behavior and controls

Create `arty_m3_camera_top.sv` rather than modifying the proven Milestone 2 demo top in place. Keep the top specific to the OV7670 so the signal directions, expected identity, and debug messages stay obvious.

Suggested controls:

- `BTN0`: global reset;
- `BTN1`: restart camera initialization;
- `BTN2`: clear sticky camera/FIFO errors;
- `BTN3`: request an immediate UART status report;
- `SW0`: sensor test pattern off/on, if supported;
- `SW1`: raw-camera diagnostic mode versus Sobel mode;
- `SW2`: optional RGB565 byte-order override during initial bring-up;
- `SW3`: freeze the most recent frame statistics for inspection.

Suggested LEDs:

- `LD4`: existing heartbeat;
- `LD5`: camera initialization complete;
- `LD6`: frame activity, stretched long enough to see;
- `LD7`: sticky camera, SCCB, frame-format, or FIFO error.

Do not use a one-camera-clock LED pulse directly; stretch or toggle it in the system clock domain.

---

## 7. UART reporting

UART should report short status lines, not image data. Keep baud rate parameterized. The existing 115200 rate is adequate for status, while a later 1,000,000 or 2,000,000 baud option can be tested if more frequent telemetry or small thumbnails are useful.

Recommended startup lines:

```text
M3 OV7670 RESET
M3 OV7670 ID=7670 XCLK=24000000 CFG=PASS WR=0123 NACK=0000
```

Recommended per-frame line:

```text
M3 F=0000002A LINE=240 PIX=76800 RAWCRC=12345678 OUT=75684 SOBCRC=9ABCDEF0 ERR=0000
```

Use hexadecimal for CRC/error bitmasks and decimal or fixed-width hexadecimal consistently for counts. Document the exact representation.

Suggested error bits:

| Bit | Meaning |
|---:|---|
| 0 | SCCB NACK or timeout |
| 1 | Unexpected chip ID |
| 2 | Odd active-byte count |
| 3 | Wrong line length |
| 4 | Wrong frame line count |
| 5 | FIFO overflow |
| 6 | FIFO underflow/protocol misuse |
| 7 | Coordinate jump |
| 8 | Sobel input/output count mismatch |

At 115200 baud, a raw 320x240 grayscale frame would take roughly 6.7 seconds using normal 8N1 UART framing, before any packet or text-protocol overhead, and cannot provide useful live frame rate. Raising UART baud helps debugging but does not make UART the final image transport. Ethernet remains the correct full-frame path.

---

## 8. Verification strategy

### 8.1 Camera bus model

Create a simple behavioral DVP camera model rather than relying only on hand-driven waveforms. It should generate:

- programmable `PCLK` unrelated in phase to 100 MHz;
- `VSYNC`, horizontal blanking, and `HREF`;
- two bytes per RGB565 pixel;
- 8x8, 16x16, and 320x240 frames;
- selectable high-byte-first and low-byte-first ordering;
- deterministic color bars and coordinate-encoded pixels;
- programmable blanking gaps;
- malformed cases such as odd bytes, short lines, long lines, and truncated frames.

Keep the model readable and camera-like. It does not need to reproduce analog sensor behavior.

### 8.2 Unit testbenches

`tb_camera_xclk.sv` should verify:

- XCLK frequency and duty cycle;
- camera reset/power-down startup timing;
- restart behavior.

`tb_sccb_master.sv` should verify:

- write and read transaction bit ordering;
- open-drain SDA release;
- ACK, NACK, timeout, start, repeated-start if used, and stop;
- correct SCCB clock divider.

`tb_camera_register_init.sv` should verify:

- every table entry is issued in order;
- required delays are honored;
- end-of-table detection;
- retry or fail behavior after NACK;
- correct `0x21`/`0x42`/`0x43` address notation at the controller boundary;
- expected `PID=0x76` and `VER=0x70` handling;
- chip-ID mismatch reporting.

`tb_dvp_rgb565_capture.sv` should verify:

- both byte orders;
- exact first and last coordinates;
- complete 320x240 count;
- blanking does not create pixels;
- line/frame transitions clear half-pixel state;
- malformed lines set the expected error.

`tb_camera_stream_cdc.sv` should verify:

- unrelated clock frequencies and randomized phase;
- no loss, duplication, or reordering;
- FIFO occupancy behavior;
- explicit overflow test;
- reset from either domain without stale valid output.

`tb_camera_stream_adapter.sv` should verify:

- RGB565-to-grayscale values and coordinate latency;
- raw-bypass and Sobel modes;
- complete 8x8, 16x16, and 320x240 frames;
- exact Sobel output count and CRC against the existing Python model.

### 8.3 End-to-end regression

The complete Milestone 3 test should use two asynchronous clocks and prove:

```text
DVP camera model
  -> RGB565 byte assembly
  -> asynchronous FIFO
  -> RGB565 grayscale
  -> existing Sobel pipeline
  -> output count and CRC
  -> UART status reporter
```

Minimum cases:

- all-black RGB565;
- all-white RGB565;
- red, green, and blue fields;
- vertical and horizontal color bars;
- checkerboard;
- coordinate-encoded image;
- fixed-seed pseudorandom RGB565;
- two consecutive frames;
- long and short blanking;
- reset during SCCB configuration;
- reset during an active line;
- one intentionally malformed frame followed by a valid recovery frame.

Every task/function in new testbenches should have a short purpose comment immediately before its definition, matching the existing project style.

### 8.4 Assertions

Add lightweight assertions where XSim supports them:

- camera `x` remains below 320 and `y` remains below 240;
- `pixel_valid` only occurs inside an active frame and line;
- an active line contains an even byte count;
- every valid frame contains 240 active lines and 76,800 pixels;
- FIFO write never occurs while full;
- FIFO read never occurs while empty;
- coordinates do not jump or move backward inside a frame;
- the first system-domain pixel is `(0,0)` and the last is `(319,239)`;
- the Sobel output remains inside `(1,1)` through `(318,238)`;
- no output remains valid after reset until a fresh complete 3x3 window exists.

---

## 9. Hardware bring-up order

Do not connect everything and debug the final Sobel result first. Use the following stages and keep evidence from each one.

### Stage A: electrical inspection

1. Record the camera module, voltage levels, power rails, and complete FPGA pin mapping.
2. Check power and ground continuity before programming.
3. Confirm the FPGA will not drive camera-output pins.
4. Confirm the camera connector orientation.

### Stage B: XCLK and reset only

1. Build a top that drives only XCLK, reset, power-down, heartbeat, and UART.
2. Measure XCLK frequency and duty cycle with an oscilloscope or logic analyzer.
3. Confirm camera power consumption is reasonable and no device overheats.
4. Confirm reset/power-down timing matches the datasheet.

### Stage C: OV7670 SCCB/chip ID

1. Address the sensor as 7-bit `0x21` and read identity before applying the full table.
2. Confirm `PID=0x76` and `VER=0x70`; also record optional manufacturer bytes `0x7F`, `0xA2`.
3. Run the configuration table and report write/NACK counts.
4. Test restart initialization with `BTN1`.

Do not proceed if chip ID or configuration ACK behavior is unexplained.

### Stage D: raw timing with ILA

Add an Integrated Logic Analyzer clocked by `cam_pclk` and probe:

- `VSYNC`;
- `HREF`;
- `cam_d`;
- byte phase;
- assembled RGB565 pixel;
- camera-domain `x` and `y`;
- frame/line error flags.

Capture the first line, one middle line, and the final line. Confirm sync polarity, byte order, 640 active bytes per line, 320 pixels per line, and 240 lines per frame.

### Stage E: clock-domain crossing

Probe FIFO write/read enables, full/empty, occupancy, camera coordinates, and system-domain coordinates. Confirm:

- no overflow over many frames;
- the system stream begins at `(0,0)` and ends at `(319,239)`;
- frame count and pixel count remain exact;
- resetting and restarting does not leak stale pixels.

### Stage F: raw grayscale validation

Enable the OV7670 color bar using the supplied datasheet's documented test-pattern controls. Record the exact combination of `COM17[3]`, `COM7[1]`, `SCALING_XSC[7]`, and `SCALING_YSC[7]` used. Compare observed RGB565 values, grayscale CRC, frame count, and representative pixel samples with a Python model.

### Stage G: Sobel integration

Connect the proven camera stream to `grayscale_rgb565.sv` and `conv_pipeline_top.sv`.

For every complete 320x240 camera frame confirm:

- 76,800 accepted input pixels;
- 75,684 Sobel output pixels;
- zero coordinate/protocol errors;
- zero FIFO overflow/underflow errors;
- stable deterministic CRC when the sensor test pattern is enabled;
- visible pass/activity LEDs and correct UART status.

### Stage H: sustained run

Run for at least ten minutes or a documented frame count. Confirm:

- no growing error counters;
- no FIFO overflow;
- frame count advances continuously;
- line and pixel counts remain exact;
- UART reporting does not interfere with capture;
- reset and reinitialization recover without reprogramming the FPGA.

---

## 10. Constraints and implementation targets

Milestone 3 should meet the following implementation targets:

- 100 MHz system timing passes with positive setup and hold slack;
- `cam_pclk` is declared and timed as a separate clock;
- camera data and sync input delays are derived from the OV7670's 15 ns setup and 8 ns hold data timing, the chosen sampling edge, and board skew;
- XCLK uses a suitable clock resource and output path;
- CDC analysis recognizes the asynchronous FIFO and reset synchronizers;
- no camera data bit crosses clock domains independently;
- all camera ports have verified package pins and correct I/O standards;
- no unconstrained clocks remain;
- 320x240 capture produces no FIFO overflow at the selected camera clock;
- the existing two Sobel line buffers still infer as block RAM;
- no inferred latches, combinational loops, multiple drivers, or unexplained width truncations remain;
- all remaining warnings are listed and explained in the implementation notes.

Recommended artifacts:

```text
docs/milestone3_camera_hardware_contract.md
docs/milestone3_camera_logic_walkthrough.md
docs/milestone3_camera_simulation_results.txt
docs/milestone3_camera_hardware_validation.md
docs/milestone3_uart_capture.txt
docs/timing_summary_milestone3.rpt
docs/utilization_milestone3.rpt
docs/camera_ila_capture_first_line.png
docs/camera_ila_capture_frame_boundary.png
```

---

## 11. Recommended implementation order

### Phase 0: document and map the OV7670 module

- Record the direct-DVP connector labels and the module manufacturer/part number if available.
- Confirm voltage compatibility and power requirements.
- Record the module schematic/datasheet revision.
- Map all camera pins to FPGA package pins.
- Confirm 24 MHz XCLK, SCCB address `0x21`, expected identity `0x7670`, sync polarity, and byte order.

### Phase 1: create camera clock and configuration path

- Implement XCLK and startup reset/power-down timing.
- Implement and simulate the SCCB master.
- Add the sensor-specific register ROM.
- Read chip ID and report configuration state over UART.
- Validate XCLK and SCCB on hardware before pixel capture.

### Phase 2: capture RGB565 in the camera domain

- Implement the DVP camera model.
- Implement byte assembly, coordinates, and frame/line error checks.
- Run directed and malformed-frame testbenches.
- Validate raw camera timing with ILA.

### Phase 3: cross into the system domain

- Add the asynchronous FIFO wrapper.
- Stress unrelated clock rates and randomized phase in simulation.
- Add overflow/underflow/occupancy counters.
- Prove exact system-domain coordinates and counts in ILA/UART.

### Phase 4: integrate grayscale and Sobel

- Connect RGB565 conversion with aligned valid/coordinates.
- Add raw-camera bypass and Sobel modes.
- Compare deterministic test-pattern CRCs with Python.
- Run complete 320x240 and consecutive-frame regressions.

### Phase 5: finish the hardware demo

- Add final UART status and LED behavior.
- Capture chip ID, configuration, raw frame, FIFO, and Sobel evidence.
- Run a sustained multi-frame test.
- Generate timing/utilization reports and the final bitstream.

---

## 12. Milestone 3 definition of done

- [ ] Direct-DVP module labels, absence of FIFO control pins, datasheet revision, and any available module schematic are recorded.
- [ ] Camera power and I/O voltages are confirmed safe for the Arty A7.
- [ ] Every camera signal has a verified direction and package pin.
- [ ] XCLK frequency, duty cycle, and startup timing are verified in simulation and on hardware.
- [ ] SCCB master passes ACK, NACK, timeout, read, and write tests.
- [ ] OV7670 identity is read correctly on hardware: `PID=0x76`, `VER=0x70`, with the observed values recorded.
- [ ] Sensor register sequence is sourced, documented, and reports zero unexplained NACKs.
- [ ] OV7670 produces stable 320x240 RGB565 timing.
- [ ] RGB565 byte order and sync polarity are proven with ILA evidence.
- [ ] Each active line contains exactly 640 bytes and 320 pixels.
- [ ] Each complete frame contains exactly 240 lines and 76,800 pixels.
- [ ] Odd bytes, malformed lines, truncated frames, and resets are detected and recover cleanly.
- [ ] Asynchronous FIFO passes simulation with unrelated clocks and randomized phase.
- [ ] No pixels are lost, duplicated, or reordered across clock domains.
- [ ] FIFO overflow and underflow remain zero during sustained hardware capture.
- [ ] RGB565-to-grayscale conversion remains bit-exact with aligned coordinates.
- [ ] Camera test pattern produces the expected raw/grayscale checksum.
- [ ] Camera-to-Sobel integration produces exactly 75,684 outputs per complete frame.
- [ ] Deterministic camera test pattern produces the expected Sobel checksum.
- [ ] UART reports chip ID, configuration state, frame counts, pixel counts, CRCs, and errors.
- [ ] Camera and system clocks meet timing with no unconstrained clocks.
- [ ] Camera I/O delays and CDC paths are correctly constrained and reviewed.
- [ ] Synthesis, implementation, route, DRC, and bitstream generation complete successfully.
- [ ] A sustained hardware run completes without growing error counters.
- [ ] Timing, utilization, UART, ILA, and board-validation evidence are saved under `docs/`.

Completing this milestone leaves Milestone 4 with a clean input: a continuous, validated Sobel stream and stable frame metadata ready for Ethernet packetization, without mixing network debugging into camera bring-up.

---

## 13. Work not yet completed

The sensor has now been selected as the OV7670. At the time this plan was written, the following Milestone 3 work does not exist in the repository:

- the module manufacturer/part number, schematic, onboard regulator/level-shifting details, and final camera-to-Arty pin assignment;
- a verified electrical connection and pin map;
- camera XCLK/reset/power-down logic;
- SCCB configuration RTL and a sourced QVGA RGB565 OV7670 register table;
- parallel DVP byte capture;
- camera pixel-clock constraints;
- asynchronous camera-to-system FIFO;
- camera debug counters and UART reporter;
- DVP camera simulation model and camera testbenches;
- ILA probes/captures;
- camera-connected top level and bitstream;
- physical chip-ID, frame-count, checksum, or sustained-run evidence.

Milestone 3 should not be marked complete until every applicable item in the definition of done has physical evidence, not only a successful Vivado build.

---

## 14. Primary OV7670 references

- Project-authoritative local file: `OV7670_DS (1.01).fm - OV7670.pdf`, supplied by the camera owner; OmniVision preliminary datasheet version 1.01, July 8, 2005; SHA-256 `C58749ACCCA5E39E950081F957EEE3DF72FC4B66B633CF168F03E87E8F202425`.
- [Matching online copy of the OmniVision OV7670/OV7171 preliminary datasheet, version 1.01](https://robu.in/wp-content/uploads/2019/05/OV7670-Preliminary-Datasheet.pdf)
- [OmniVision OV7670/OV7171 Implementation Guide, version 1.0, September 2 2005](https://web.mit.edu/6.111/www/f2017/tools/OV7670app.pdf)

The links are mirrors of OmniVision documents because this legacy part no longer has a convenient current product page. Use the supplied version-1.01 PDF for sensor identity and electrical/timing values. Its checksum is recorded above so future work can confirm it is using the same revision.
