# Milestone 7 hardware validation

## Current state

The profile-qualified image was programmed on the Arty A7. M4 UDP echo, M7 v2
STATUS, build ID `0x4d370001`, v2 START/STOP, and the setup check passed. The
`safe`, `medium`, and `fast` OV7670 profiles are hardware-qualified at
7.503, 15.006, and 30.012 FPS. Each profile completed 1,000 grayscale and 1,000
Sobel frames with zero host integrity errors and zero FPGA error flags. The
final candidate additionally fixes synthetic/live arbitration, host START frame
retention, metric capture, and the output-overflow clock crossing, and expands
controlled synthetic compute to 32 independent lanes. It has passed all 12 RTL
benches, all 13 host tests, and routed signoff but still needs its final board
rerun. Per the current validation schedule, the board is intentionally not
attached. The physical FPGA-versus-OpenCV comparison, threshold mode, dashboard
workflow, and activity demonstration remain open until this exact image is
programmed.

The board-independent implementation is complete. All 12 RTL testbenches pass,
the Vivado 2026.1 synthesis check finishes with zero errors and zero critical
warnings, and the timing-gated implementation script produces a fully routed
bitstream for `xc7a100tcsg324-1`.

| Routed implementation metric | Result |
|---|---:|
| Core clock | 200.000 MHz |
| WNS / TNS | +0.030 ns / 0.000 ns |
| WHS / THS | +0.024 ns / 0.000 ns |
| Failing setup / hold endpoints | 0 / 0 |
| Failed routes | 0 |
| Slice LUTs | 17,731 (27.97%) |
| Slice registers | 35,303 (27.84%) |
| Block RAM tiles | 47 (34.81%) |
| DSPs | 0 (0.00%) |

The final candidate bitstream is:

`artifacts/m7_runs/build/arty_m7_camera_ethernet_top.bit`

The build also mirrors it to
`vivado_project_m7/arty_conv_m7.runs/impl_1/arty_m7_camera_ethernet_top.bit`.
Use the stable `artifacts/` copy in Hardware Manager because resetting a Vivado
implementation run removes the project-run copy.

SHA-256:
`d6666a158584773f10465d0522cf54dd1ca304ec009b39494d6166383ec26b15`

The original routed failure is preserved in
`docs/milestone7_timing_summary_fail.rpt`: WNS was -1.289 ns, TNS was
-41.811 ns, and 143 setup endpoints failed. The real 200 MHz critical path was
the unregistered synthetic-pixel expression driving the line-buffer BRAM. The
synthetic calculation is now split across two short registered stages while
retaining one accepted pixel per core cycle. The M7-only XDC also marks the
system/core asynchronous-FIFO boundary and the camera-clock reset synchronizer
as the asynchronous crossings they are. Later hardware runs exposed a synthetic
completion compare path, live-input FIFO overflow during synthetic ownership,
and a metric-capture race at live resume. The completion path is now a
frames-remaining counter, live writes are intentionally blocked during the run,
and host CONFIGURE/START releases live input on the next `(0,0)` frame boundary.
The clean final result is archived in
`docs/milestone7_timing_summary_pass.rpt`.

## Synthetic benchmark arbitration

The first 1,000-frame synthetic board run completed the expected 76,800 inputs
and 75,684 outputs with no valid gaps, but set FPGA error `0x2000`: the camera
continued filling the live input FIFO while synthetic mode paused its reader.
Blocking live writes removed that error. A second board run then completed with
`error_flags=0x0000`, but automatic live resume replaced the synthetic 76,800
cycle interval before the status snapshot reached the host.

The final RTL keeps live input blocked after synthetic completion so the metrics
remain stable. The next CONFIGURE or START records a resume request, and the
camera path reopens only on coordinate `(0,0)`. The self-checking core test holds
live input asserted during synthetic operation, verifies no overflow and the
synthetic interval, then explicitly resumes and verifies the block clears. The
synthetic path now processes 32 independent frames concurrently at 200 MHz.
Lane `n` uses `lane0 ^ ((n * 0x1d) & 0xff)`. The reported CRC rotates and XORs
all 32 lane CRCs, so every physical pipeline must contribute. A complete batch
starts every 76,800 cycles and therefore reports an aggregate 2,400-cycle
per-frame interval: 0.012 ms or 83,333.33 frames/s. For the exact 1,000-frame
contract, 32 batches are required, so the static report conservatively uses
2,457.6 cycles or 0.012288 ms per requested frame. This is controlled synthetic
compute throughput, not live camera cadence. The final hardware run remains
pending until the exact hash above is programmed.

The five single-thread OpenCV runs in `milestone7_static_projection.md`
measured a 0.070253 ms median against the stronger exact
`spatialGradient`/`convertScaleAbs`/saturating-add formulation. The resulting
5.7172x is explicitly a routed-RTL projection. Final acceptance still requires
the programmed image to return the expected `0x9e562313` combined CRC and its
hardware cycle counters.

## Camera profile qualification

The invalid original medium/fast table changed register `0x73` from `0xF1` to
`0xF0` while retaining `COM14=0x19`. On hardware this doubled the line-clock
span, produced zero active image bytes, and set error flag `0x0004`. The fixed
profiles preserve the matched QVGA scaler pair `COM14=0x19` and `0x73=0xF1`;
only `CLKRC` changes the sensor input clock rate.

| Profile | Pages 13/14 readback | Frame period cycles | Active geometry | Grayscale | Sobel |
|---|---:|---:|---:|---:|---:|
| `safe` | `0x01041911f1` | 13,327,999 | 640 bytes x 240 lines | 1,000 at 7.503 FPS, 0 errors | 1,000 at 7.503 FPS, 0 errors |
| `medium` | `0x00041911f1` | 6,663,999 | 640 bytes x 240 lines | 1,000 at 15.006 FPS, 0 errors | 1,000 at 15.006 FPS, 0 errors |
| `fast` | `0x40041911f1` | 3,331,999 | 640 bytes x 240 lines | 1,000 at 30.012 FPS, 0 errors | 1,000 at 30.012 FPS, 0 errors |

The raw qualification transcript is
`docs/milestone7_profile_qualification.txt`. It applies to profile-qualified
bitstream SHA-256
`36c1a93fe1d2eda60a40f01d171eaf8ab66a3f3905105a2236e5810d87f82c90`.
The board was returned to `safe`, and `scripts/python/m7_setup_check.py` then
passed without an FPGA error flag.

The final output-overflow pulse crossing is repaired with a core-domain sticky
bit and a two-flop level synchronizer; synthetic busy is registered before its
synchronizer. The remaining CDC structures and all post-route DRC findings are
explicitly classified in `docs/milestone7_cdc_drc_classification.md`.
Post-route DRC has zero errors and 42 warnings: 20 REQP-1839 RAMB36 reset-
control warnings, 20 REQP-1840 RAMB18 reset-control warnings, and two report-
limit notices. Generated timing, utilization, CDC, DRC, checkpoint, and hash
evidence is kept under the ignored `artifacts/m7_runs/` directory.

## Reproduction sequence

Run these in order after connecting the hardware:

1. Re-run `scripts/run_m7_simulations.tcl` if RTL changes and preserve every
   `PASS:` line.
2. Re-run `scripts/check_m7_synthesis.tcl` and
   `scripts/build_m7_bitstream.tcl` if RTL or constraints change.
3. Review `docs/milestone7_cdc_drc_classification.md` against the generated
   CDC/DRC reports.
4. Program the timing-clean image with
   `& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode batch -source scripts/program_m7_device.tcl -notrace`.
5. Run `py -3 scripts/python/m7_setup_check.py` and retain the output. It
   checks adapter assignment, M4 UDP echo, M7 build ID, and v2 START/STOP.
6. Run `py -3 scripts/python/qualify_m7_profiles.py --frames 1000`. It qualifies
   `safe`, `medium`, then `fast`, reads back pages 13/14, verifies 640 active
   RGB565 bytes by 240 lines, and runs 1,000 grayscale plus 1,000 Sobel frames
   per profile with zero integrity errors.
7. Run the full benchmark and archive JSON, CSV, Markdown, UART status, and
   the activity event log under `docs/` only after review.

## Acceptance checklist

- [x] Safe profile preserves the M6 approximately 7.5 FPS behavior.
- [x] Medium profile sustains at least 15 FPS with zero camera/FIFO/protocol errors.
- [x] Fast profile is stable near 30 FPS with zero camera/FIFO/protocol errors.
- [x] SCCB timing readback matches the selected profile.
- [x] M4 UDP echo still passes.
- [ ] M5-compatible v1 streaming still passes.
- [x] M7 v2 STATUS returns build ID `0x4d370001`, and v2 START/STOP pass.
- [x] Reference Sobel and thresholded Sobel are bit-exact against the golden model.
- [ ] Synthetic core counters report latency, interval, pixel totals, and CRC.
- [ ] Five controlled OpenCV runs and five FPGA runs satisfy the 1.05x contract,
  or the report explicitly records the failed comparison.
- [x] Five controlled OpenCV runs and the routed-RTL projection clear the 1.05x
  target; this does not replace the unchecked physical item above.
- [ ] Dashboard setup, clean stop, snapshot, benchmark cancel, and log export pass.
- [ ] Idle/activity demonstration produces matching visible transitions and log rows.
- [x] Routed setup and hold timing pass at the 200 MHz core target.
- [x] All remaining CDC/DRC findings are resolved or explicitly classified.
