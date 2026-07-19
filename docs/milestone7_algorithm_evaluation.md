# Milestone 7 algorithm evaluation

## Decision

The committed refinement is an optional binary threshold after the existing
3x3 Sobel L1 magnitude. Reference Sobel remains the default and is unchanged
for M5/M6 compatibility. The threshold is frame-locked: a new request is
sampled only with the first cropped output pixel `(x=1,y=1)`, so a frame cannot
contain two threshold settings.

| Mode | Input | Output | Golden model |
|---|---|---|---|
| Grayscale diagnostic | RGB565 camera | 320x240 8-bit grayscale | `camera_stream_adapter` |
| Reference Sobel | 320x240 grayscale | 318x238 saturated `abs(Gx)+abs(Gy)` | `m7_algorithms.sobel_l1` |
| Thresholded Sobel | Reference Sobel | 318x238, `255` when value `>= threshold`, otherwise `0` | `m7_algorithms.threshold_sobel` |

The border policy is the existing two-pixel crop. Sobel arithmetic is signed
integer L1 magnitude with saturation at 255; thresholding does not alter the
reference result when disabled.

## Software evidence

The host regression passes the exact OpenCV comparison, threshold boundary,
shape validation, activity monitor, protocol, and result-schema tests:

```text
python scripts/python/run_m7_host_tests.py
Ran 12 tests ... OK
```

The equivalent OpenCV operation is single-threaded and processes the same two
deterministic 320x240 inputs used by the FPGA batch (`lane0` and
`lane0 ^ 0xA5`). Both results use the same 318x238 crop. The comparison checks
the combined CRC `lane0_crc ^ rotate_left(lane1_crc, 1)`, so synthesis cannot
silently merge or remove either hardware lane. The board has qualified all
three physical camera profiles, but the final five-run/1,000-sample
FPGA-versus-OpenCV comparison is not yet claimed against the newest bitstream.

## RTL evidence

The relevant self-checking benches are:

- `tb_m7_threshold_sobel`: reference passthrough, threshold boundary, and no
  mid-frame configuration tear;
- `tb_conv_pipeline_320`: full 320x240 reference Sobel regression and CRC;
- `tb_m7_core_metrics`: frame interval, latency, accepted/produced totals, and
  valid-gap accounting;
- `tb_m7_accelerated_core`: four requested frames through two independent
  parallel lanes, exact combined CRC, a 96-cycle aggregate interval at 16x12,
  no live-input overflow during synthetic ownership, and frame-boundary resume.

The M7 build uses `m7_accelerated_pipeline` only for the M7 top. Its synthetic
benchmark feeds two independent Sobel pipelines at 200 MHz and reports an
aggregate per-frame interval of 38,400 cycles (0.192 ms, 5,208.33 frames/s).
This is controlled compute throughput for two independent frames; live camera
streaming remains one lane at the selected 7.5/15/30 FPS sensor rate. M5 remains
the default (`M7_ENABLE=0`) and retains the proven 100 MHz pipeline and v1 host
protocol behavior.

## Not yet measured

The final routed build and camera-rate matrix are recorded in
`docs/milestone7_hardware_validation.md`. A camera corpus, image-quality
comparison, threshold-mode hardware CRC, and controlled FPGA-versus-OpenCV
compute result are still pending and belong in the benchmark record.
