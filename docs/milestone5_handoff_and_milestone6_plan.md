# Milestone 5 handoff and Milestone 6 live-view/benchmark plan

## Milestone 5 handoff status

Milestone 5 is complete and was accepted on physical hardware on July 18,
2026. The integrated Arty A7-100T bitstream now performs this complete path:

```text
OV7670 RGB565 camera
  -> 320x240 grayscale
  -> four-stage 3x3 Sobel accelerator
  -> 318x238 8-bit cropped result
  -> validated M5 UDP packets
  -> laptop frame reassembly
```

Acceptance evidence:

- all four M5 XSim targets passed;
- routed timing passed with WNS `0.634 ns` and WHS `0.036 ns`;
- the tested bitstream SHA-256 is
  `8c9577a1ff240642bf1aef7a37178feb910d6b0b2e218a7052d94dc535e7bc00`;
- the laptop retained 216 consecutive 318x238 Sobel frames, sequence 0 through
  215, with valid PGM headers and exact 75,684-byte rasters;
- the integrated bitstream continued to answer ARP and pass M4 UDP echo on
  port 4000.

The generated PGM directory is intentionally ignored. Concise evidence lives
in `milestone5_hardware_results.txt` and
`milestone5_hardware_validation.md`.

## Authoritative M5 artifacts

- `rtl/top/arty_m5_camera_ethernet_top.sv`: integrated FPGA top
- `rtl/integration/m5_*.sv`: session, FIFO, packetizer, scheduler, and snapshot logic
- `constraints/arty_a7_m5_camera_ethernet.xdc`: camera plus Ethernet pin/timing constraints
- `scripts/python/camera_udp_receiver.py`: proven PGM capture tool
- `docs/milestone5_camera_ethernet_contract.md`: on-wire protocol
- `docs/milestone5_camera_ethernet_logic_walkthrough.md`: implemented architecture
- `docs/milestone5_simulation_results.txt`: automated evidence
- `docs/milestone5_hardware_validation.md`: build and physical evidence
- `docs/milestone5_hardware_results.txt`: concise physical result
- `docs/timing_summary_milestone5.rpt`: routed timing
- `docs/utilization_milestone5.rpt`: routed resource use

Keep the M5 bitstream and the dependency-free PGM receiver runnable throughout
M6. They are the fallback when a display or OpenCV problem must be separated
from an FPGA/network problem.

## Known limitations carried into M6

- The stream is 320x240 grayscale or 318x238 Sobel, not full-color video.
- UDP provides detection, not retransmission. Damaged frames are rejected.
- The current observed display feed is camera/network limited. It is not a
  direct measurement of the 100 MHz Sobel core's maximum compute throughput.
- The routed CDC/DRC reports contain classified vendor/reset/FIFO warnings that
  remain a non-blocking cleanup item.
- The 216-frame accepted archive is shorter than the original 300-frame
  characterization target.
- OpenCV and NumPy are not part of the Python standard library and must be
  installed before the M6 viewer or benchmark can run.

## Milestone 6 objective

Make the processed stream visibly useful on the laptop and produce a
repeatable, honest performance comparison between the FPGA Sobel datapath and
an equivalent OpenCV CPU implementation.

M6 is primarily a host-software milestone. The existing M5 bitstream already
supports continuous Sobel and grayscale sessions, so no FPGA protocol change
is required for the first M6 implementation.

## Live viewer contract

`camera_udp_viewer.py` shall:

1. bind `192.168.10.1:4001` and request a continuous M5 session;
2. validate header fields, packet placement, payload CRC-32, and frame sequence;
3. display every complete frame in an OpenCV window without writing every frame to disk;
4. overlay stream mode, dimensions, frame sequence, rolling FPS, average FPS,
   integrity errors, and discontinuity state;
5. stop cleanly with `Q`, `Esc`, window close, or Ctrl+C;
6. save a selected validated PGM when `S` is pressed;
7. send STOP before closing the socket.

Initial display modes:

- `--stream sobel`: show the 318x238 FPGA-processed Sobel result;
- `--stream gray`: show the 320x240 grayscale diagnostic stream.

## Benchmark contract

The benchmark must not compare unrelated measurements or assume that the FPGA
will beat an optimized laptop library. It must report these separately:

### 1. Laptop OpenCV kernel time

Run OpenCV on 320x240 8-bit grayscale frames using the FPGA-equivalent rule:

```text
Gx = Sobel(gray, dx=1, dy=0, ksize=3)
Gy = Sobel(gray, dx=0, dy=1, ksize=3)
result = saturate_to_u8(abs(Gx) + abs(Gy))
result = result[1:-1, 1:-1]
```

Report warm-up count, sample count, mean, median, p95, minimum, maximum, and
derived frames/s. Time only the OpenCV kernel for this measurement.

### 2. Measured end-to-end stream performance

Measure complete validated frames at the laptop for two separate sessions:

- FPGA Sobel stream: camera -> FPGA Sobel -> UDP -> laptop;
- CPU path: camera -> FPGA grayscale -> UDP -> laptop -> OpenCV Sobel.

Report time to first frame, inter-frame FPS, session duration, and every
integrity counter. This measures the complete product path and will normally
be limited by camera timing and network/host behavior rather than the kernel.

### 3. FPGA RTL throughput estimate

The Sobel pipeline accepts one input pixel per 100 MHz fabric clock once full.
For 320x240 input, the clearly labeled throughput estimate is:

```text
76,800 pixels / 100,000,000 pixels/s = 0.768 ms of active pixel clocks
estimated continuous-input throughput = 1,302.08 frames/s
```

This is not end-to-end latency and must never be presented as measured camera
FPS. The benchmark records it beside, not in place of, physical measurements.

## Implemented M6 host files

```text
scripts/python/m6_stream_client.py
scripts/python/camera_udp_viewer.py
scripts/python/benchmark_m6_opencv.py
scripts/python/test_m6_stream_client.py
scripts/python/test_m6_opencv.py
scripts/python/requirements-m6.txt
```

The benchmark emits machine-readable JSON and CSV with OS, processor, Python,
OpenCV, NumPy, and OpenCV-thread metadata so published numbers can be repeated.

The final physical result is recorded in `milestone6_benchmark_results.md`.
All six full-size golden patterns matched OpenCV bit-for-bit, the 300-frame
Sobel and CPU-path sessions completed without packet/frame integrity errors,
and the laptop displayed 300 consecutive FPGA Sobel frames.

## M6 setup and commands

Install the host dependencies once:

```powershell
py -3 -m pip install -r scripts/python/requirements-m6.txt
```

Use the already-tested M5 bitstream and configure `Ethernet 2` as
`192.168.10.1/24`, with no gateway. Set `SW1=0` so the requested session mode
is honored and `SW2=1` to enable streaming.

Display the FPGA Sobel stream:

```powershell
py -3 scripts/python/camera_udp_viewer.py --stream sobel
```

Display grayscale for comparison:

```powershell
py -3 scripts/python/camera_udp_viewer.py --stream gray
```

Run a CPU-only OpenCV kernel benchmark without the board:

```powershell
py -3 scripts/python/benchmark_m6_opencv.py --cpu-only --cpu-samples 1000
```

Run the complete two-session physical comparison:

```powershell
py -3 scripts/python/benchmark_m6_opencv.py --frames 300
```

Default result files:

```text
docs/m6_benchmark_results.json
docs/m6_benchmark_results.csv
```

## Phased M6 validation

### Phase 0: preserve the M5 baseline

- Re-run one-frame PGM capture and one M4 UDP echo.
- Keep the M5 protocol and bitstream unchanged.

Acceptance: both known-good commands pass before OpenCV is involved.

### Phase 1: live display

- Install OpenCV and NumPy.
- Run Sobel and grayscale viewers.
- Verify window close, `Q`/Esc, snapshot `S`, and STOP behavior.
- Run at least 300 displayed FPGA Sobel frames with zero integrity errors.

Acceptance: the user sees a responsive live stream and the final viewer
summary reports no missing, duplicate, reordered, malformed, CRC, or frame-gap
errors.

### Phase 2: CPU and end-to-end benchmark

- Run at least 20 untimed OpenCV warm-up iterations.
- Measure at least 1,000 synthetic CPU kernel samples.
- Run 300 live FPGA Sobel frames.
- Run 300 live grayscale-plus-OpenCV frames.
- Save JSON and CSV results.

Acceptance: results contain all required timing statistics, integrity counters,
system metadata, and explicit labels distinguishing estimates from measurements.

### Phase 3: evidence and interpretation

- Save one viewer screenshot.
- Archive benchmark JSON/CSV and console transcript.
- Add a concise M6 results document explaining which path is faster and why.
- State camera/network limits and CPU library optimization honestly.

Acceptance: another person can reproduce the commands and understand the
comparison without reading RTL or inferring what was timed.

## Milestone 6 completion contract

M6 is complete when:

1. the laptop displays the continuous FPGA Sobel stream;
2. 300 displayed frames finish with zero integrity errors;
3. grayscale display also works from the same M5 bitstream;
4. the exact OpenCV Sobel baseline is benchmarked with warm-up and at least
   1,000 timed CPU samples;
5. 300-frame FPGA and CPU end-to-end sessions are recorded;
6. JSON and CSV include system metadata and all required statistics;
7. the result explains measured FPS, CPU kernel time, and FPGA throughput
   estimate as different quantities;
8. M5 PGM capture and M4 UDP echo still pass.

## Final M6 result

Milestone 6 passed on July 18, 2026:

- 300 FPGA Sobel frames displayed at 7.473 FPS;
- 30 grayscale frames displayed at 7.236 FPS;
- final physical FPGA Sobel benchmark: 300 frames at 7.50314 FPS;
- final grayscale-plus-OpenCV benchmark: 300 frames at 7.50311 FPS;
- all missing, duplicate, reordered, malformed, CRC, and sequence-gap counters were zero;
- exact OpenCV kernel, 1,000 controlled samples: 0.629 ms mean, 0.504 ms median, 1.116 ms p95;
- live OpenCV kernel, 300 samples: 1.371 ms mean, 1.322 ms median, 2.140 ms p95;
- end-to-end FPGA/CPU FPS ratio: 1.000004, showing the present camera path is the bottleneck;
- integrated M4 UDP echo remained passing.

The supported performance interpretation and machine-readable artifacts are
in `milestone6_benchmark_results.md`, `m6_benchmark_results.json`, and
`m6_benchmark_results.csv`.

## Outside Milestone 6

- changing the OV7670 resolution or frame rate
- RGB color display
- JPEG/H.264 compression
- browser/WebRTC streaming
- neural-network inference
- DDR frame buffering
- retransmission or a reliable transport protocol
- claiming a speedup not supported by the measured data
