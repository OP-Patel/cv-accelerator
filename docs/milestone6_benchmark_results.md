# Milestone 6 live-view and benchmark results

## Final status

**PASS - Milestone 6 completed on July 18, 2026.**

The laptop displayed the live FPGA Sobel stream, displayed the grayscale
diagnostic stream, and completed the final FPGA-versus-OpenCV benchmark. The
existing M5 bitstream and protocol were reused without an FPGA rebuild.

## Test environment

```text
Board:          Digilent Arty A7-100T
Camera:         OV7670, 320x240 RGB565 input
Ethernet:       DP83848J, 100 Mb/s full duplex
Host adapter:   Ethernet 2, 192.168.10.1/24
Host OS:        Windows 11 10.0.26200
CPU identifier: Intel64 Family 6 Model 170 Stepping 4
Python:         3.13.7
OpenCV:         5.0.0
NumPy:          2.4.3
OpenCV threads: 1
```

The OpenCV operation was proven pixel-for-pixel against all six full-size
patterns from `golden_sobel.py` before performance testing.

## Live viewer acceptance

FPGA Sobel display:

```text
frames=300
display FPS=7.473
missing=0 duplicate=0 reordered=0 malformed=0 crc=0 frame_gaps=0
discontinuity=1
```

Grayscale display check:

```text
frames=30
display FPS=7.236
missing=0 duplicate=0 reordered=0 malformed=0 crc=0 frame_gaps=0
discontinuity=1
```

The single discontinuity marker is on the first recovered frame after each
new streaming session. No packet loss, corruption, reordering, malformed
packet, or frame-sequence gap accompanied it.

## Final benchmark

Command:

```powershell
py -3 scripts/python/benchmark_m6_opencv.py --frames 300 --cpu-samples 1000
```

### Controlled OpenCV CPU kernel

This measures only the exact OpenCV Sobel kernel on a deterministic synthetic
320x240 frame after 20 warm-up iterations.

| Metric | Result |
|---|---:|
| Samples | 1,000 |
| Mean | 0.629 ms |
| Median | 0.504 ms |
| p95 | 1.116 ms |
| Minimum | 0.220 ms |
| Maximum | 50.062 ms |
| Throughput derived from mean | 1,591 frames/s |

The 50 ms maximum is an operating-system scheduling outlier; median and p95
are included so the result is not represented by one statistic alone.

### FPGA RTL throughput estimate

The FPGA pipeline accepts one input pixel per 100 MHz clock once full:

```text
76,800 input pixels / 100,000,000 pixels/s = 0.768 ms
estimated continuous-input throughput = 1,302 frames/s
```

In the isolated compute comparison, OpenCV's mean throughput was about 1.22
times the FPGA estimate. This FPGA value is an RTL throughput estimate, not a
measurement of camera-to-display latency.

### Physical FPGA Sobel path

| Metric | Result |
|---|---:|
| Complete frames | 300 |
| Time to first frame | 196.849 ms |
| Session duration | 40.048 s |
| Inter-frame rate | 7.50314 FPS |
| Missing/duplicate/reordered/malformed/CRC/frame gaps | all zero |
| First-frame discontinuity markers | 1 |

### Physical grayscale plus OpenCV path

| Metric | Result |
|---|---:|
| Complete frames | 300 |
| Time to first frame | 132.214 ms |
| Session duration | 39.983 s |
| Inter-frame rate | 7.50311 FPS |
| Live OpenCV mean | 1.371 ms |
| Live OpenCV median | 1.322 ms |
| Live OpenCV p95 | 2.140 ms |
| Live OpenCV throughput from mean | 729 FPS |
| Missing/duplicate/reordered/malformed/CRC/frame gaps | all zero |
| First-frame discontinuity markers | 1 |

The FPGA's 0.768 ms compute estimate is about 1.79 times faster than the
1.371 ms OpenCV mean measured while the host was concurrently receiving and
reassembling the live grayscale stream.

## Interpretation

The end-to-end FPGA/CPU FPS ratio was `1.000004`: effectively identical. Both
paths are limited to about 7.5 FPS by the current OV7670 capture/timing path,
not by Sobel compute.

Therefore the supported conclusion is:

- the FPGA successfully performs and offloads Sobel before pixels reach the laptop;
- the FPGA does not increase current camera-to-laptop frame rate;
- isolated optimized OpenCV is faster than this small 100 MHz FPGA core;
- under the live receive workload, the FPGA compute estimate is faster than
  the measured host OpenCV kernel;
- both compute paths have far more capacity than the current 7.5 FPS input.

This is an honest accelerator result: deterministic streaming/offload and a
working visible system, without claiming an end-to-end speedup the camera
cannot expose.

## Preserved baseline

Before the benchmark, M4 UDP echo passed on the integrated bitstream:

```text
PASS udp sent=1 received=1 missing=0 corrupt=0 reordered=0 avg_ms=0.412
```

Machine-readable final results are stored in:

```text
docs/m6_benchmark_results.json
docs/m6_benchmark_results.csv
```
