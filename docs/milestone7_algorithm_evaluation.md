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
Ran 10 tests ... OK
```

The equivalent OpenCV operation is single-threaded, uses the same deterministic
320x240 coordinate pattern, crops to 318x238, and reports CRC agreement. The
full five-run/1,000-sample comparison is intentionally not claimed until the
board is attached.

## RTL evidence

The relevant self-checking benches are:

- `tb_m7_threshold_sobel`: reference passthrough, threshold boundary, and no
  mid-frame configuration tear;
- `tb_conv_pipeline_320`: full 320x240 reference Sobel regression and CRC;
- `tb_m7_core_metrics`: frame interval, latency, accepted/produced totals, and
  valid-gap accounting;
- `tb_m7_accelerated_core`: sustained no-gap two-frame core-domain regression.

The M7 build uses `m7_accelerated_pipeline` only for the M7 top. M5 remains the
default (`M7_ENABLE=0`) and retains the proven 100 MHz pipeline and v1 host
protocol behavior.

## Not yet measured

No camera corpus, image-quality comparison, routed timing, FPGA resource delta
against M6, or hardware CRC/throughput result is recorded here. Those require
the Arty A7, OV7670, and Ethernet adapter and belong in the hardware and
benchmark records after physical qualification.
