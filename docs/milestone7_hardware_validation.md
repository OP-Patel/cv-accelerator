# Milestone 7 hardware validation

## Current state

The Arty A7, OV7670, Ethernet cable, and host adapter are not attached for
this implementation pass. No M7 board benchmark, camera-rate claim, routed
timing claim, bitstream hash, or physical activity demonstration is asserted.

The board-independent implementation is in place and the existing synthesized
checkpoint reports that `arty_m7_camera_ethernet_top` elaborates on
`xc7a100tcsg324-1`:

| Pre-route synthesis metric | Result |
|---|---:|
| Slice LUTs | 13,539 (21.35%) |
| Slice registers | 28,265 (22.29%) |
| Block RAM tiles | 16 (11.85%) |
| DSPs | 0 (0.00%) |

That checkpoint is synthesis evidence only and predates the final coherent
camera-counter snapshot cleanup. It is not a routed timing result; rerun the
synthesis script before treating the numbers as release evidence.

The prior CDC report contains the expected XPM asynchronous-FIFO pointer
findings and the inherited reset/PHY crossings from M5, plus M7's intentional
toggle-and-stable-bus control crossings. The final run must classify each
finding in the archived report; no new crossing should be waived silently.
The generated report is kept under the ignored `artifacts/m7_runs/synthesis/`
directory and can be regenerated with `scripts/check_m7_synthesis.tcl`.

## Required physical sequence

Run these in order after connecting the hardware:

1. Run `scripts/run_m7_simulations.tcl` and preserve every `PASS:` line.
2. Run `scripts/check_m7_synthesis.tcl`; review CDC/DRC findings and record
   the classified report.
3. Run `scripts/build_m7_bitstream.tcl`; record routed WNS/WHS, utilization,
   DRC/CDC, Vivado version, and the SHA-256 file it emits.
4. Program `vivado_project_m7/arty_conv_m7.runs/impl_1/arty_m7_camera_ethernet_top.bit`.
5. Run `py -3 scripts/python/m7_setup_check.py` and retain the output. It
   checks adapter assignment, M4 UDP echo, M7 build ID, and v2 START/STOP.
6. Use the dashboard to qualify `safe`, then `medium`, then `fast`. For each
   profile, read back pages 13/14, verify 640 active RGB565 bytes by 240 lines,
   and run 1,000 grayscale plus 1,000 Sobel frames with zero integrity errors.
7. Run the full benchmark and archive JSON, CSV, Markdown, UART status, and
   the activity event log under `docs/` only after review.

## Acceptance checklist

- [ ] Safe profile preserves the M6 approximately 7.5 FPS behavior.
- [ ] Medium profile sustains at least 15 FPS with zero camera/FIFO/protocol errors.
- [ ] Fast profile is either stable near 30 FPS or has a measured bottleneck report.
- [ ] SCCB timing readback matches the selected profile.
- [ ] M4 UDP echo and M5-compatible v1 streaming still pass.
- [ ] Reference Sobel and thresholded Sobel are bit-exact against the golden model.
- [ ] Synthetic core counters report latency, interval, pixel totals, and CRC.
- [ ] Five controlled OpenCV runs and five FPGA runs satisfy the 1.05x contract,
  or the report explicitly records the failed comparison.
- [ ] Dashboard setup, clean stop, snapshot, benchmark cancel, and log export pass.
- [ ] Idle/activity demonstration produces matching visible transitions and log rows.
- [ ] Routed timing passes; all CDC/DRC findings are resolved or classified.
