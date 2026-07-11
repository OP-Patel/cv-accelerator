# Milestone 1 handoff and sizable Milestone 2 plan

## Executive summary

Milestone 1 now provides the reusable board-debug foundation needed for the accelerator: synchronized reset, debounced buttons and switches, heartbeat and switch LEDs, a synthesizable UART transmitter, periodic/manual status messages, self-checking simulation, a serial-monitor utility, Arty A7 constraints, and a working Vivado project/build flow.

The RTL, behavioral verification, and physical-board validation portions of Milestone 1 are complete. Vivado 2026.1 successfully synthesized, placed, routed, and generated a bitstream for the design before the final UART pin correction. That run reported zero synthesis errors, zero implementation errors, no failed routes, estimated setup WNS of 4.552 ns, and estimated hold WHS of 0.118 ns. The corrected hardware behavior was subsequently tested and reported valid by the project owner, including LEDs, reset, switches/buttons, and readable COM4 UART operation.

Milestone 1 is functionally closed. The corrected mapping is FPGA RX on A9 and FPGA TX on D10, and physical operation has been confirmed. One repository-hygiene action remains: the generated `impl_1` report currently present on disk predates the XDC correction and still displays the old mapping, so fresh generated reports/bitstream should replace those stale artifacts before they are used as final archival evidence. This does not change the recorded physical PASS result.

Milestone 2 should be a substantial, independently verifiable streaming image-processing subsystem. Its recommended deliverable is a one-pixel-per-clock grayscale/Sobel pipeline with BRAM-backed line storage, explicit window and border semantics, bit-exact Python comparison, randomized regression tests, a synthetic-image hardware test, and UART-reported checksums. Camera and Ethernet integration remain deliberately outside Milestone 2.

---

## 1. What Milestone 1 finished

### 1.1 Clock, heartbeat, and reset

- The design uses the Arty A7 100 MHz oscillator on FPGA pin E3.
- A 27-bit free-running counter provides a visible heartbeat on `LD4` through counter bit 26.
- The heartbeat changes state every 67,108,864 clocks, or approximately 0.671 seconds at 100 MHz.
- `BTN0` is used as a real active-high reset input rather than being left unused.
- Reset assertion is asynchronous so the system enters reset immediately.
- Reset release passes through two flip-flops so all synchronous logic leaves reset on a clock edge.
- The reset registers carry Vivado's `ASYNC_REG` attribute.

### 1.2 Buttons, switches, and LEDs

- `BTN1`, `BTN2`, and `BTN3` are constrained and passed through independent synchronizer/debouncer instances.
- `SW0` through `SW3` are constrained and independently synchronized/debounced.
- The default debounce period is 1,000,000 clocks, or 10 ms at 100 MHz.
- A state change is accepted only after the synchronized input remains different from the current accepted value for the complete debounce interval.
- `LD5`, `LD6`, and `LD7` mirror debounced `SW0`, `SW1`, and `SW2`.
- `SW3` is represented in the UART hexadecimal switch field because the heartbeat consumes the remaining single-color LED.
- A rising edge on any debounced additional button requests an immediate UART status line.
- Holding a button does not continuously retrigger because the top level detects only the cleaned low-to-high transition.

### 1.3 USB-UART path

- The top level exposes `uart_rx` and `uart_tx`.
- The FPGA transmit pin is D10, which feeds the FTDI/PC receive direction.
- The FPGA receive pin is A9, which receives the FTDI/PC transmit direction.
- The current Milestone 1 implementation is transmit-only; `uart_rx` is synchronized for future use but no receiver or echo path is implemented.
- The transmitter implements 115200 baud, eight data bits, no parity, and one stop bit.
- At 100 MHz, each bit lasts 868 clocks. This produces approximately 115207 baud, an error of about +0.0064%.
- The line is high when idle, followed by a low start bit, eight least-significant-bit-first data bits, and a high stop bit.
- `busy` covers the complete ten-bit frame, including the entire stop-bit duration.
- A new `send` request is accepted only while the transmitter is idle.

### 1.4 UART message generator

The top-level status line is:

```text
M1 OK SW=0xN\r\n
```

where `N` is the hexadecimal value of the four debounced switches.

- The first line is requested after the synchronizers and debouncers have had time to settle.
- A new line is requested every five seconds.
- Any cleaned rising edge on `BTN1` through `BTN3` requests another line.
- Switches are snapshotted at the start of a line, preventing a mid-line switch transition from changing the hexadecimal character unexpectedly.
- The message controller explicitly waits for the UART to accept each send pulse and then waits for `busy` to return low before selecting the next character.
- Multiple requests received while a line is active are coalesced into one pending follow-up line rather than overflowing a queue.

### 1.5 Verification and host tools

- `tb_uart_tx.sv` checks reset/idle behavior, start bit, every data bit, stop bit, `busy`, completion, and rejection of a second send while busy.
- `tb_arty_m1_bringup_top.sv` checks reset assertion/release, heartbeat movement, switch LED behavior, UART activity, and the first transmitted ASCII character.
- Both testbenches passed in Vivado 2026.1 XSim.
- `scripts/run_simulations.tcl` runs both behavioral simulations.
- `scripts/python/serial_monitor.py` lists ports, opens a selected port at 115200 8N1, prints timestamped lines, supports a finite capture duration, and can append evidence to a file.
- `scripts/create_project.tcl` contains every Milestone 1 RTL, constraint, and simulation source.
- `scripts/build_bitstream.tcl` runs synthesis and implementation, generates the bitstream, and writes timing/utilization reports under `docs/`.

### 1.6 Milestone 1 closure record and remaining artifact cleanup

Physical validation was reported successful on 2026-07-11:

- heartbeat LED operation passed;
- reset assertion/release passed;
- switch and LED behavior passed;
- manual button behavior passed;
- USB-UART enumeration on COM4 passed;
- readable 115200 8N1 status text passed.

The remaining archival actions are:

1. Regenerate the on-disk implementation artifacts so `arty_bringup_top_io_placed.rpt` records FPGA RX on A9 and FPGA TX on D10.
2. Copy fresh timing and utilization reports into `docs/` and record final WNS/WHS and resource counts.
3. Capture a representative terminal session under `docs/uart_terminal_milestone1.txt` if a durable raw transcript is desired.
4. Commit the final reports and validation notes with the Milestone 1 source revision.

---

## 2. Milestone 2 objective

Build and verify the central streaming convolution datapath without introducing camera timing, Ethernet protocols, DDR, or MicroBlaze.

The milestone should accept a raster-ordered grayscale pixel stream and produce a Sobel edge stream at one accepted pixel per clock after pipeline fill. It should prove three things independently:

1. The line-storage/window architecture produces the correct 3x3 neighborhood.
2. The signed Sobel arithmetic and saturation are bit-exact.
3. The complete streaming pipeline behaves correctly under real raster blanking gaps and on FPGA hardware using a synthetic source.

This scope is large enough to demonstrate FPGA architecture, BRAM inference, pipelining, coordinate alignment, signed fixed-width arithmetic, verification methodology, and hardware/software co-validation while remaining small enough to debug thoroughly.

---

## 3. Recommended Milestone 2 interfaces

### 3.1 Input stream

Use an explicit raster stream:

```systemverilog
input  logic        clk;
input  logic        reset;
input  logic        in_valid;
input  logic [X_W-1:0] in_x;
input  logic [Y_W-1:0] in_y;
input  logic [7:0]  in_gray;
```

Rules:

- Pixels arrive in left-to-right, top-to-bottom order.
- State advances only when `in_valid` is high.
- `in_x` and `in_y` describe the accepted pixel on that clock.
- Gaps between lines and frames are legal; a gap must not advance shift registers or line-buffer write positions.
- Milestone 2 does not require backpressure because the eventual camera source cannot be paused. The pipeline must sustain one valid pixel every clock.
- Assertions in simulation should detect unexpected coordinate jumps while `in_valid` is high.

### 3.2 Output stream

```systemverilog
output logic        out_valid;
output logic [X_W-1:0] out_x;
output logic [Y_W-1:0] out_y;
output logic [7:0]  out_pixel;
```

Every pipeline stage must delay `valid`, `x`, and `y` by exactly the same number of cycles as its pixel data.

### 3.3 Border policy

Use a cropped-interior policy for the first implementation:

- No output is asserted until a complete 3x3 window exists.
- Input coordinates must satisfy `in_x >= 2` and `in_y >= 2` before the window is valid.
- The corresponding output coordinate is the window center: `out_x = in_x - 1`, `out_y = in_y - 1`, delayed through the arithmetic pipeline.
- A `W x H` input therefore produces `(W-2) x (H-2)` output pixels.

This policy is recommended because it is unambiguous and naturally streamable. Emitting zero-valued borders while preserving full frame dimensions can be added later, but it complicates ordering at the top and left edges because those output samples are needed before the complete window exists.

---

## 4. Recommended RTL structure

```text
rtl/conv/
  grayscale_rgb565.sv
  line_buffer_3x3.sv
  window_3x3.sv
  sobel3x3.sv
  saturate_u8.sv
  conv_pipeline_top.sv
  synthetic_pixel_source.sv
  stream_checksum.sv
```

### 4.1 `grayscale_rgb565.sv`

Although the first convolution tests can inject `in_gray` directly, include a separately tested RGB565-to-grayscale block so it is ready for later camera integration.

Recommended first conversion:

```text
gray = (77*R8 + 150*G8 + 29*B8 + 128) >> 8
```

The coefficients sum to 256 and approximate the standard luminance weights. Expand RGB565 channels to eight bits before multiplication. Pipeline the multiplies/addition if needed for 100 MHz. Keep this block optional at the Milestone 2 top-level boundary so the core Sobel tests are not coupled to color-conversion bugs.

### 4.2 `line_buffer_3x3.sv`

Store the previous two image rows using inferred simple dual-port block RAM or two row memories.

Important implementation rules:

- Parameterize `IMAGE_WIDTH`, initially 320.
- Write only on `in_valid`.
- Do not clear every memory element during reset; doing so often prevents BRAM inference and creates a large reset network.
- Reset only pointers, row-selection state, and validity metadata.
- Ignore memory contents until at least two complete rows have been accepted.
- Verify the read-during-write behavior expected from the inferred RAM and code the pipeline latency explicitly.

The output for each accepted input pixel should provide the same column from the current row, previous row, and row before that.

### 4.3 `window_3x3.sv`

Use three horizontal three-deep shift-register chains, one per row supplied by the line buffer.

On every `in_valid` clock:

1. Shift each row's two older samples left.
2. Insert the newest sample for that row.
3. Assert `window_valid` only when two prior rows and two prior columns exist.
4. Associate the window with center coordinate `(in_x-1, in_y-1)`.

The nine output names should encode row and column, such as `p00` through `p22`, with a documented convention that `p00` is top-left and `p22` is bottom-right.

### 4.4 `sobel3x3.sv`

Use the standard kernels:

```text
Gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22
Gy = -p00 - 2*p01 - p02 + p20 + 2*p21 + p22
```

Then compute:

```text
edge = saturate(abs(Gx) + abs(Gy))
```

Width analysis:

- Each pixel is unsigned 8-bit, from 0 through 255.
- The positive or negative Sobel coefficient magnitude sums to four.
- `Gx` and `Gy` therefore range from -1020 through +1020.
- Signed 11-bit arithmetic is required because 10-bit signed arithmetic stops at +511.
- Each absolute magnitude can reach 1020.
- Their sum can reach 2040 and fits in 11 unsigned bits.
- Saturation maps values greater than 255 to 255 without wrapping.

Recommended pipeline:

1. Stage A: register grouped positive and negative partial sums for Gx/Gy.
2. Stage B: subtract partial sums to produce signed Gx/Gy.
3. Stage C: compute absolute values and their unsigned sum.
4. Stage D: saturate to eight bits and register the output.

This structure should sustain one pixel per clock even though an individual pixel has several cycles of latency.

### 4.5 `saturate_u8.sv`

Make saturation its own tiny combinational module and exhaustively unit-test it:

- Input 0 produces 0.
- Input 1 through 254 pass unchanged.
- Input 255 produces 255.
- Every input greater than 255 produces 255.

Keeping it separate prevents silent truncation from masquerading as saturation.

### 4.6 `conv_pipeline_top.sv`

This module connects line storage, window generation, Sobel arithmetic, coordinate delays, and output valid generation.

It should expose counters useful for hardware validation:

- accepted input pixels;
- valid output pixels;
- frames started/completed;
- protocol/coordinate errors;
- rolling output checksum.

These counters can later become debug/status registers without changing the convolution blocks.

---

## 5. Verification strategy

### 5.1 Python golden model

Add:

```text
scripts/python/golden_sobel.py
scripts/python/generate_m2_vectors.py
```

The model must implement the exact same rules as RTL:

- identical grayscale rounding, if grayscale conversion is tested;
- identical cropped border policy;
- `abs(Gx) + abs(Gy)` rather than Euclidean magnitude;
- identical saturation to 255;
- deterministic raster ordering.

Avoid relying only on OpenCV's default Sobel behavior because its border rules, output depth, and rounding can differ. A small explicit NumPy implementation should be the source of truth; OpenCV can be used as a secondary visual comparison.

### 5.2 Unit testbenches

Recommended files:

```text
sim/tb/tb_grayscale_rgb565.sv
sim/tb/tb_line_buffer_3x3.sv
sim/tb/tb_window_3x3.sv
sim/tb/tb_sobel3x3.sv
sim/tb/tb_conv_pipeline.sv
```

Tests should be self-checking and terminate with a nonzero/fatal result on the first mismatch.

### 5.3 Directed image cases

At minimum, compare RTL against Python for:

- all-black image;
- all-white image;
- single bright pixel;
- vertical step edge;
- horizontal step edge;
- diagonal edge;
- checkerboard;
- horizontal ramp;
- vertical ramp;
- impulse at each valid/border-adjacent location;
- pseudorandom image generated from a fixed seed.

Start with 8x8 and 16x16 images because every pixel/window can be inspected. Then run at least one complete 320x240 regression.

### 5.4 Streaming-stress cases

Functional image equality is not sufficient. Also test transport behavior:

- Randomly insert `in_valid` gaps between pixels.
- Insert realistic horizontal and vertical blanking gaps.
- Reset midway through a row and verify no output remains valid afterward until a new complete window exists.
- Run two frames back-to-back and confirm line-buffer/frame state does not leak across the boundary.
- Confirm the exact number of outputs: `(W-2)*(H-2)` for each complete frame.
- Confirm the first output coordinate is `(1,1)` and the last is `(W-2,H-2)`.
- Assert that output coordinates remain aligned with output pixels through every pipeline stage.

### 5.5 Assertions and coverage

Add lightweight SystemVerilog assertions where supported:

- `out_valid` must never assert before two rows and two columns are available.
- `in_x` must remain within the configured image width.
- Raster coordinates must not move backward inside a frame.
- Output coordinates must remain within the cropped range.
- The output count at frame completion must match the expected count.

Record which directed cases and random seeds were run so failures are reproducible.

---

## 6. Hardware validation without a camera

Milestone 2 should end with a real FPGA demonstration, but the input should remain deterministic.

### 6.1 Synthetic source

Create `synthetic_pixel_source.sv` that generates a small image or streams a `.mem`-initialized ROM/BRAM image. Useful selectable patterns are:

- black;
- white;
- vertical edge;
- horizontal edge;
- checkerboard;
- stored pseudorandom test image.

Use switches to select the pattern and a debounced button to start/restart a frame.

### 6.2 Checksum-based result

Sending every processed pixel over 115200 UART would be slow and would couple datapath validation to host-transfer timing. Instead:

1. Stream the deterministic image through the convolution pipeline at full fabric speed.
2. Accumulate a CRC32 or a documented rolling checksum over valid output pixels.
3. Compare the hardware result with the Python-computed expected checksum.
4. Report a concise line over the existing UART, for example:

```text
M2 SOBEL PAT=2 IN=76800 OUT=75684 CRC=4A91D20F PASS
```

For 320x240 cropped Sobel output, the expected count is `318*238 = 75,684` pixels.

### 6.3 Suggested LED mapping

- `LD4`: existing heartbeat;
- `LD5`: test running;
- `LD6`: test completed/pass;
- `LD7`: mismatch/protocol error, sticky until reset.

Keep the UART status detailed and the LEDs immediate. A sticky error LED is much more useful than a short error pulse.

---

## 7. Vivado and implementation targets

Milestone 2 should meet these implementation goals:

- 100 MHz system-clock timing passes with positive setup and hold slack.
- The main pipeline accepts one pixel per clock after fill.
- The two line buffers infer BRAM rather than thousands of resettable flip-flops.
- No unconstrained top-level clocks or I/O ports are introduced.
- No inferred latches, combinational loops, multiple drivers, or width-truncation warnings remain unexplained.
- Sobel constant multiplications by two synthesize as shifts/wiring, not unnecessary general multipliers.
- Utilization and timing reports are captured under `docs/` for comparison with later milestones.

Recommended report artifacts:

```text
docs/timing_summary_milestone2.rpt
docs/utilization_milestone2.rpt
docs/milestone2_simulation_results.txt
docs/milestone2_hardware_validation.md
docs/milestone2_uart_capture.txt
```

---

## 8. Recommended implementation order

### Phase 0: archive Milestone 1

- Regenerate reports so the archived implemented I/O table matches the already validated corrected UART pins.
- Save a short COM4 transcript if raw terminal evidence is desired.
- Commit clean Milestone 1 reports and hardware notes.

### Phase 1: freeze numerical and stream contracts

- Document image dimensions, coordinate meaning, border policy, pixel order, reset behavior, valid-gap behavior, and arithmetic widths.
- Implement the explicit Python golden model before the main RTL.
- Generate small directed test vectors and expected outputs.

### Phase 2: build and verify primitives

- Implement and exhaustively test `saturate_u8.sv`.
- Implement and test optional RGB565 grayscale conversion.
- Implement line buffers and prove the two delayed rows independently.
- Implement the 3x3 horizontal window and prove every tap location using coordinate-encoded pixels.

### Phase 3: implement the Sobel arithmetic pipeline

- Add signed width-safe Gx/Gy calculations.
- Pipeline absolute value, magnitude approximation, and saturation.
- Delay coordinates and valid alongside the data.
- Run directed kernel-level tests before connecting line storage.

### Phase 4: integrate the complete streaming core

- Connect line buffer, window, Sobel, and saturation blocks.
- Add output counters and assertions.
- Compare complete 8x8, 16x16, and randomized images against Python.
- Add valid-gap, reset, and multi-frame stress tests.

### Phase 5: build the synthetic hardware demonstration

- Add pattern/ROM source, checksum block, and UART result formatting.
- Use switches for test selection and a button for start.
- Add run/pass/error LEDs.
- Confirm hardware checksum matches Python for every built-in pattern.

### Phase 6: close timing and documentation

- Run synthesis and implementation at 100 MHz.
- Confirm BRAM inference and record LUT/FF/BRAM/DSP usage.
- Resolve or explicitly document every warning.
- Capture timing, utilization, simulation, UART, and board evidence.
- Update README and mark Milestone 2 complete only after software and hardware checks pass.

---

## 9. Milestone 2 definition of done

Milestone 2 is complete only when all of the following are true:

- [ ] Stream, coordinate, reset, valid-gap, and border contracts are documented.
- [ ] Python golden model produces deterministic expected data and checksums.
- [ ] Grayscale conversion, if enabled, matches the golden rounding exactly.
- [ ] Line buffers infer BRAM and produce correct prior-row samples.
- [ ] Every 3x3 window tap is proven correctly aligned.
- [ ] Sobel signed arithmetic uses sufficient width and cannot wrap silently.
- [ ] Saturation is exhaustively tested.
- [ ] Complete RTL is bit-exact for all directed cases and fixed-seed random images.
- [ ] A 320x240 regression passes.
- [ ] Valid gaps, resets, and consecutive frames pass.
- [ ] The pipeline accepts one pixel per clock after fill.
- [ ] Synthesis and implementation pass at 100 MHz.
- [ ] Timing and utilization reports are committed under `docs/`.
- [ ] Synthetic hardware patterns produce the expected output counts/checksums.
- [ ] UART reports a hardware `PASS` result for every built-in pattern.
- [ ] Hardware evidence and exact commands are recorded.

Completing this scope will leave Milestone 3 with a clean boundary: the camera work only needs to produce the already-defined raster stream, rather than debugging camera capture and convolution arithmetic simultaneously.
