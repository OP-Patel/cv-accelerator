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
Ran 13 tests ... OK
```

The equivalent OpenCV operation is single-threaded
`spatialGradient` followed by `convertScaleAbs` and a saturating `add`. It is
bit-exact to the FPGA's cropped, saturated L1 Sobel result and substantially
faster than the earlier pair of `cv2.Sobel` calls followed by NumPy arithmetic.
Both paths cycle through the same 32 deterministic 320x240 inputs; lane `n`
uses `lane0 ^ ((n * 0x1d) & 0xff)`. Both results use the same 318x238 crop.
The comparison checks
`xor(rotate_left(lane_crc[n], n) for n in 0..31) == 0x9e562313`, so synthesis
cannot silently merge or remove a hardware lane.

The board-independent five-run, 1,000-frame result measured a 0.070253 ms
median OpenCV kernel time. The routed FPGA structure accepts 32 independent
frames every 76,800 core cycles. Charging the 32-batch hardware workload
(including the final 24 unused lanes) against exactly 1,000 requested frames
gives a conservative 0.012288 ms projected frame time and 5.7172x projected
throughput. This clears the 1.05x target statically, but the newest bitstream's
physical counters and CRC still must confirm it.

## RTL evidence

The relevant self-checking benches are:

- `tb_m7_threshold_sobel`: reference passthrough, threshold boundary, and no
  mid-frame configuration tear;
- `tb_conv_pipeline_320`: full 320x240 reference Sobel regression and CRC;
- `tb_m7_core_metrics`: frame interval, latency, accepted/produced totals, and
  valid-gap accounting;
- `tb_m7_accelerated_core`: 64 requested frames through 32 independent
  parallel lanes, exact combined CRC, a 6-cycle aggregate interval at 16x12,
  no live-input overflow during synthetic ownership, and frame-boundary resume.

The M7 build uses `m7_accelerated_pipeline` only for the M7 top. Its synthetic
benchmark feeds 32 independent Sobel pipelines at 200 MHz and reports a
full-batch aggregate per-frame interval of 2,400 cycles (0.012 ms, 83,333.33
frames/s). Lane 0 remains the live-camera pipeline; lanes 1 through 31 are
enabled only for the controlled synthetic benchmark. Live camera streaming
therefore remains one lane at the selected 7.5/15/30 FPS sensor rate. M5
remains the default (`M7_ENABLE=0`) and retains the proven 100 MHz pipeline and
v1 host protocol behavior.

## Not yet measured

The final routed build and camera-rate matrix are recorded in
`docs/milestone7_hardware_validation.md`, and the explicit non-hardware result
is in `docs/milestone7_static_projection.md`. A camera corpus, image-quality
comparison, threshold-mode hardware CRC, and controlled physical
FPGA-versus-OpenCV compute result are still pending.
