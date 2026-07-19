# Milestone 6 handoff and Milestone 7 optimization/application plan

## Milestone 6 handoff status

Milestone 6 is complete and was accepted on physical hardware on July 18,
2026. The laptop can display continuous grayscale and FPGA Sobel streams from
the M5 bitstream, save selected frames, and run a controlled OpenCV comparison.

Verified baseline:

- 300 displayed FPGA Sobel frames completed with zero packet/frame integrity
  errors;
- the final FPGA Sobel stream measured `7.50314 FPS`;
- the final grayscale-plus-OpenCV stream measured `7.50311 FPS`;
- controlled OpenCV Sobel measured `0.629 ms` mean over 1,000 samples;
- the FPGA Sobel core remains a one-input-pixel-per-100-MHz-clock pipeline;
- M4 UDP echo still passes on the integrated bitstream;
- representative grayscale and FPGA Sobel captures are in `docs/assets/`.

The authoritative result is `milestone6_benchmark_results.md`. Machine-readable
measurements are in `m6_benchmark_results.json` and
`m6_benchmark_results.csv`.

## Known limitations carried into M7

- The verified camera cadence is approximately 7.5 FPS. This is not a viewer,
  Sobel-compute, or 100 Mb/s Ethernet throughput limit.
- The current camera timing table is compiled into RTL and has only one
  hardware-qualified profile.
- The FPGA exposes grayscale and fixed Sobel L1 magnitude; threshold, smoothing,
  direction, and alternative kernels are not runtime-selectable.
- The M6 benchmark distinguishes kernel time and end-to-end FPS, but it does
  not yet sweep camera rates, algorithm variants, host CPU load, FPGA resource
  cost, or long-duration stability.
- The live viewer demonstrates processing but does not yet solve a specific
  user-facing problem.
- Generated Vivado projects, raw captures, and durable validation evidence need
  stricter separation.
- Classified CDC/DRC warnings and stale milestone-era duplication remain cleanup
  work.

## Milestone 7 objective

Turn the working prototype into a faster, better-characterized, configurable
edge-processing appliance that beats the equivalent OpenCV implementation in a
fair compute benchmark and provides one complete application with an easy
browser-based control surface:

```text
OV7670 camera
  -> selectable validated camera-rate profile
  -> grayscale and refined edge processing in the FPGA
  -> integrity-checked UDP stream and statistics
  -> laptop Streamlit dashboard, activity monitor, logs, and benchmark report
```

M7 prioritizes measured improvement and a repeatable demonstration. It must not
trade away the known-good M5/M6 path or claim 30 FPS until hardware evidence
supports it.

### Overarching acceleration goal

M7 must optimize the FPGA implementation until it beats the exact equivalent
single-thread OpenCV operation on the validation laptop. The comparison must use
the same input frames, algorithm, border crop, saturation, warm-up policy, and
sample count.

The M6 reference numbers are:

```text
FPGA 100 MHz active-pixel estimate: 0.768 ms/frame
OpenCV controlled mean:             0.629 ms/frame
OpenCV controlled median:           0.504 ms/frame
```

These numbers show that the current core does not yet win the isolated
comparison. M7 must replace the FPGA estimate with measured core cycles and
measured sustained synthetic-source throughput. The required result is at least
a 5% FPGA throughput advantage over the median of a fresh controlled OpenCV
run. Kernel compute, camera-to-laptop FPS, request-to-first-frame time, and host
CPU usage must remain separately labeled measurements.

## Workstream 1: establish the real camera-rate limit

Before changing dividers, add measurements that make the source timing visible:

- count 100 MHz cycles between consecutive camera `VSYNC` edges;
- count `PCLK` edges per line and per frame;
- report measured frame period, active bytes, active lines, and FIFO peak
  occupancy through UART status;
- read back the timing-related SCCB registers after initialization;
- retain the current 7.5 FPS setup as the named `safe` profile.

This separates sensor timing from FPGA capture, FIFO, packetizer, Ethernet, and
viewer behavior.

## Workstream 2: higher-FPS camera profiles

Create explicit profiles rather than silently replacing the proven table:

| Profile | Purpose | Required status |
|---|---|---|
| `safe` | Existing approximately 7.5 FPS settings | Preserve bit-for-bit behavior |
| `medium` | Remove one conservative divider | Hardware-qualify at at least 15 FPS |
| `fast` | Target nominal QVGA camera rate | Attempt and characterize 30 FPS |

Change only one clock/scaling setting per experiment. For every profile:

1. read back the SCCB timing registers;
2. verify 640 RGB565 bytes by 240 active lines;
3. validate grayscale and Sobel dimensions and CRC behavior;
4. record camera period and FIFO maximum occupancy;
5. receive at least 1,000 consecutive frames in both grayscale and Sobel modes;
6. confirm M4 UDP echo still passes;
7. archive timing, integrity, and image-quality evidence.

M7 requires a stable rate of at least 15 FPS, twice the M6 baseline. A stable
30 FPS profile is the target. If the sensor module or current direct-DVP path
cannot sustain 30 FPS, the result must identify the measured limiting stage and
retain the fastest zero-error profile.

Profile selection should initially be a simple synthesis parameter or board
control. Host-controlled profile changes are allowed only after reset/restart
semantics are defined; the camera must never change timing in the middle of a
frame.

## Workstream 3: algorithm refinement

Evaluate refinements in software on the same captured scenes before spending
FPGA resources. Candidate algorithms are:

- current Sobel `abs(Gx) + abs(Gy)` as the immutable reference;
- configurable edge threshold and binary-edge output;
- optional 3x3 smoothing before Sobel to reduce camera noise;
- separate `Gx`/`Gy` or compact direction output;
- Scharr or an approximate L2 magnitude only if the measured image-quality
  gain justifies their DSP/LUT/BRAM cost.

The committed M7 FPGA refinement is configurable thresholded Sobel. One
noise-reduction or direction feature may be added after the software comparison
and resource estimate.

Every implemented mode needs:

- a bit-exact Python/OpenCV golden model;
- directed, random-pattern, valid-gap, reset, and consecutive-frame tests;
- full 320x240 regression vectors;
- defined border, saturation, threshold, and output-dimension behavior;
- reported latency, initiation interval, BRAM, DSP, LUT, FF, and timing cost;
- runtime selection that cannot tear or change midway through a frame.

Preserve the existing grayscale and Sobel session behavior. Any protocol
extension must be versioned or additive so the M5 receiver and M6 viewer remain
useful for regression.

## Workstream 4: optimize the FPGA core to beat OpenCV

Start with the reference Sobel mode so algorithm changes cannot manufacture a
performance win. Preserve its bit-exact result while evaluating, in order:

1. deeper pipelining and removal of avoidable control-path dependencies;
2. a dedicated faster Sobel clock domain with explicit CDC boundaries;
3. a two-pixels-per-clock datapath if clock-frequency improvement alone is
   insufficient;
4. duplicated line-buffer banks or wider BRAM access only when required by the
   selected parallel architecture.

The current 100 MHz, one-pixel-per-clock estimate is approximately 1,302
frames/s. With 76,800 input pixels, illustrative compute targets are:

| Architecture | Active frame time | Approximate throughput |
|---|---:|---:|
| 125 MHz, one pixel/clock | 0.614 ms | 1,628 frames/s |
| 155 MHz, one pixel/clock | 0.495 ms | 2,018 frames/s |
| 100 MHz, two pixels/clock | 0.384 ms | 2,604 frames/s |

The actual M7 target must be recalculated from the fresh OpenCV median. A 5%
win over the M6 median would require an FPGA frame time below approximately
`0.480 ms`, or more than `160 million input pixels/s`. The table is a design
guide, not acceptance evidence.

Add hardware counters around the Sobel input and final output so reports contain:

- first-input to final-output latency in fabric cycles;
- accepted input pixels and produced output pixels;
- cycles between consecutive accepted frames under a no-gap synthetic source;
- stalls, valid gaps, and clock-domain crossings;
- routed clock frequency and timing slack for the accelerated core.

The accelerated implementation must pass the existing bit-exact full-frame
tests, consecutive-frame tests, and a sustained synthetic-source test before it
is connected to the camera. Resource growth must be reported rather than hidden.

### Fair OpenCV win contract

The performance claim is valid only when:

- OpenCV uses one thread and the exact FPGA-equivalent operation;
- both paths process the same 320x240 8-bit frames and produce the same 318x238
  result;
- at least 20 warm-up iterations and five independent 1,000-frame runs are used;
- FPGA time comes from hardware cycle counters and sustained throughput, not
  only `pixels / requested clock` arithmetic;
- the FPGA result is at least 1.05 times the median controlled OpenCV throughput;
- CPU kernel time, FPGA core time, transport time, and end-to-end FPS are shown
  in separate table columns;
- the comparison records bit-exact output agreement and the complete test
  environment.

The camera may still cap both end-to-end paths at the same FPS. That does not
invalidate a compute acceleration win, but the report must also show whether
FPGA offload reduces host CPU usage in the live application.

## Workstream 5: expanded benchmark suite

Create one M7 benchmark command that emits JSON, CSV, and a readable Markdown
summary. The benchmark matrix must cover:

- each hardware-qualified camera profile;
- FPGA grayscale, reference Sobel, and refined algorithm modes;
- equivalent single-thread OpenCV operations;
- CPU-only kernel time and live receive-plus-compute time;
- request-to-first-frame time and steady inter-frame rate;
- 300-frame quick runs and 1,000-frame acceptance runs;
- all packet, frame, FIFO, camera, and discontinuity counters;
- FPGA routed frequency, resource utilization, and labeled throughput estimate;
- host OS, CPU, Python, OpenCV, NumPy, thread count, and process-load metadata.

Report mean, median, p95, minimum, maximum, standard deviation, and sample count
for timed kernels. Do not call a reciprocal kernel-time estimate an end-to-end
FPS measurement. Do not claim true capture-to-display latency unless the camera
and host clocks are synchronized or an external visual timing method is used.

For algorithm quality, use a small curated corpus containing color bars, a
face/indoor scene, fine detail, low light, and motion. Record:

- exact-match rate where FPGA and software are intended to be identical;
- edge-pixel density and changed-pixel density;
- noise/false-edge behavior in flat regions;
- qualitative examples using the same input frame for every algorithm.

## Workstream 6: primary use case

Build a privacy-preserving edge/activity monitor on the laptop. It should use
FPGA Sobel or thresholded-edge frames as its normal input and provide:

- live processed video with rolling FPS and integrity status;
- one or more configurable regions of interest;
- per-region edge density and frame-to-frame activity score;
- a visible activity state with adjustable trigger and hold thresholds;
- timestamped CSV/JSON event logging;
- snapshot saving when an event begins;
- a grayscale diagnostic mode for setup, clearly labeled as a fallback.

This application demonstrates a plausible reason to process at the edge: the
laptop can receive a reduced, privacy-friendlier representation and useful
events rather than requiring raw color video for normal operation.

Use-case acceptance requires a recorded demonstration containing idle and
activity periods, correct event transitions, no stream-integrity errors, and a
saved event log that agrees with the visible overlay.

## Workstream 7: Streamlit setup, live dashboard, and logging

Build `m7_dashboard.py` as the normal user interface while keeping all command-
line tools available. It should have four clear views:

### Setup

- check the Python, NumPy, OpenCV, and Streamlit versions;
- detect whether `192.168.10.1` is assigned locally;
- run M4 UDP echo and M7 control/session health checks;
- display FPGA build ID, selected camera profile, algorithm mode, and link state;
- explain the exact corrective command when a check fails;
- never change an adapter or require administrator access without explicit user
  action.

### Live stream

- start and stop grayscale, reference Sobel, or refined FPGA modes;
- select camera profile, threshold, and activity-monitor ROI/settings;
- show the live processed frame, rolling/average FPS, host CPU usage, FIFO peak,
  camera period, and every integrity counter;
- surface errors visibly instead of leaving them only in the terminal;
- save a snapshot or mark an event without interrupting the stream.

### Benchmark

- launch a quick validation or full M7 benchmark;
- show progress, current phase, elapsed time, and intermediate results;
- provide a safe cancel/STOP path;
- plot FPGA/OpenCV kernel time, throughput, end-to-end FPS, CPU usage, and error
  counters without mixing those quantities;
- export the completed JSON, CSV, and Markdown report.

### Results and logs

- maintain a timestamped structured event log;
- display recent session starts/stops, profile changes, event triggers, packet
  errors, and benchmark outcomes;
- allow CSV/JSONL download;
- keep verbose generated runs under `artifacts/m7_runs/` and copy only curated
  final evidence into `docs/`.

Streamlit reruns must not create multiple UDP receivers. A background worker
should own the socket and pass validated frames/status through bounded queues.
Window close, dashboard stop, Ctrl+C, exceptions, and benchmark cancellation
must all send the protocol STOP command and release the socket.

The planned setup and launch flow is:

```powershell
py -3 -m pip install -r scripts/python/requirements-m7.txt
py -3 scripts/python/m7_setup_check.py
py -3 -m streamlit run scripts/python/m7_dashboard.py
```

Provide a small PowerShell launcher only as a convenience; the three explicit
commands remain the authoritative, debuggable path.

Dashboard acceptance requires a fresh Python environment to pass the setup
check, start and stop both stream types, run a quick benchmark, display live
metrics, and export a log without manual code edits.

## Workstream 8: cleanup and release discipline

- Keep raw captures under ignored milestone capture directories.
- Keep only curated example images and concise machine-readable results in
  version control.
- Preserve M3, M4, M5, and M6 fallback commands while removing genuinely stale
  generated paths and duplicated instructions.
- Consolidate shared Python protocol and image-processing code instead of
  copying it into each command.
- Add one host-test entry point for protocol, golden-model, viewer-helper, and
  benchmark-result schema tests.
- Resolve or explicitly classify remaining CDC/DRC warnings; introduce no new
  critical or unreviewed crossings.
- Record the final bitstream SHA-256, Vivado version, routed timing, utilization,
  and exact programming command.
- Keep the root README as the short setup/run guide and place detailed evidence
  in milestone documents.

## Proposed M7 artifacts

Names may be adjusted during implementation, but the responsibilities should
remain separate:

```text
rtl/camera/                 measured timing and selectable rate profile support
rtl/conv/                   threshold/refined edge-processing modules
rtl/integration/            frame-locked mode/configuration control
scripts/python/benchmark_m7.py
scripts/python/m7_activity_monitor.py
scripts/python/m7_dashboard.py
scripts/python/m7_setup_check.py
scripts/python/requirements-m7.txt
scripts/python/test_m7_algorithms.py
scripts/python/test_m7_results.py
scripts/run_m7_dashboard.ps1
docs/milestone7_algorithm_evaluation.md
docs/milestone7_hardware_validation.md
docs/milestone7_benchmark_results.md
docs/m7_benchmark_results.json
docs/m7_benchmark_results.csv
docs/m7_activity_demo.csv
```

## Phased execution

### Phase 0: freeze the baseline

- Re-run M4 UDP echo, one-frame M5 PGM capture, M6 viewer, and host tests.
- Record the current bitstream hash and 7.5 FPS result.

Acceptance: the existing baseline is reproducible before RTL changes.

### Phase 1: timing instrumentation and rate profiles

- Add camera timing counters/readback.
- Qualify `safe`, then `medium`, then `fast` without skipping steps.
- Select the fastest stable profile as the new default only after 1,000-frame
  grayscale and Sobel runs pass.

Acceptance: at least 15 FPS with zero camera/FIFO/protocol errors; 30 FPS is
attempted and either passed or supported by a precise bottleneck report.

### Phase 2: algorithm decision and acceleration

- Compare candidate refinements on the curated corpus.
- Optimize the reference Sobel core against the fair OpenCV win contract.
- Implement thresholded Sobel and at most one justified additional refinement.
- Pass bit-exact automated tests, measured synthetic throughput, and routed
  timing.

Acceptance: selectable algorithms are stable per frame, match their golden
models, have documented quality/resource tradeoffs, and the reference FPGA
Sobel core sustains at least 1.05 times the controlled OpenCV median throughput.

### Phase 3: dashboard and application

- Implement the setup checker and Streamlit dashboard over shared protocol
  libraries.
- Integrate the activity-monitor controls, overlays, event log, and snapshots.
- Verify clean start/stop/cancel behavior and single socket ownership.

Acceptance: a fresh environment reaches a live processed stream through the
documented setup flow and exports a correct activity log.

### Phase 4: full benchmark

- Run the full profile/algorithm/CPU benchmark matrix.
- Include five controlled OpenCV/FPGA compute runs, live host CPU usage, and
  higher-FPS camera profiles.
- Archive JSON, CSV, plots, examples, and a concise interpretation.

Acceptance: the benchmark is reproducible, proves or rejects every performance
claim from measured data, and the use case produces correct visible events and
logs during a physical demonstration.

### Phase 5: cleanup and handoff

- Remove stale generated noise from version-control scope.
- Run all preserved regressions.
- Capture final timing/utilization/CDC/DRC evidence and bitstream hash.
- Shorten the README to the final proven commands and link the detailed M7
  records.

Acceptance: a fresh checkout can be built, programmed, demonstrated, and
benchmarked without relying on an untracked local file.

## Milestone 7 completion contract

M7 is complete when:

1. the M4/M5/M6 fallback paths still pass;
2. camera timing is measured and timing-register readback is recorded;
3. a hardware profile sustains at least 15 FPS for 1,000 grayscale and 1,000
   Sobel frames with zero camera, FIFO, or protocol errors;
4. the 30 FPS target is either physically passed or has a measured bottleneck
   report;
5. thresholded Sobel plus any additional selected refinement matches its golden
   model and passes full-frame RTL regression;
6. the reference FPGA Sobel core is measured from hardware counters and sustains
   at least 1.05 times the median throughput of five controlled, equivalent
   single-thread OpenCV runs;
7. the benchmark matrix records rate, integrity, compute, host CPU, timing, and
   FPGA-resource metrics in JSON, CSV, and Markdown;
8. the Streamlit dashboard passes setup, live-view, clean-stop, quick-benchmark,
   plotting, snapshot, and log-export tests from a fresh environment;
9. the activity-monitor use case passes a physical idle/activity demonstration
   and produces a correct event log;
10. routed timing passes and all CDC/DRC findings are resolved or explicitly
    classified;

11. generated artifacts are ignored, curated evidence is tracked, and the README
   contains only the current setup, commands, results, and links;
12. the programmed bitstream hash and exact reproduction commands are archived.

## M7 implementation handoff (2026-07-19)

The board-independent implementation for this plan is now checked in:

- `arty_m7_camera_ethernet_top` wraps the pin-compatible M5 design with a
  dedicated 200 MHz core clock, asynchronous input/output FIFOs, measured core
  counters, synthetic-source benchmark control, and frame-locked thresholded
  Sobel;
- camera profiles are named `safe`, `medium`, and `fast`, with SCCB timing
  readback and camera PCLK/frame instrumentation;
- v2 control/status is additive to the v1 M5/M6 protocol, and configuration is
  rejected while a stream session is active;
- `scripts/python/run_m7_host_tests.py` passes the 12 board-independent host
  tests; the Vivado simulation list contains the preserved M5 benches plus the
  camera/profile/timing, threshold, metrics, accelerated-core, and v2-control
  benches;
- `scripts/python/m7_dashboard.py` and `m7_stream_worker.py` provide the setup,
  live, benchmark, ROI activity, snapshot, cancellation, and structured-log
  surfaces described above.
- With Vivado 2026.1 launched from
  `C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat`, all 12 board-independent
  RTL benches pass; the M7 synthesis check completes with zero errors and zero
  critical warnings.
- The first routed image failed at WNS -1.289 ns and TNS -41.811 ns because the
  synthetic-pixel expression directly drove the line-buffer BRAM and intentional
  asynchronous reset/FIFO crossings were timed synchronously. The source is now
  registered, live FIFO draining pauses during synthetic runs, and M7-specific
  clock-domain constraints classify those crossings.
- The final 200 MHz routed candidate passes at WNS +0.107 ns, TNS 0.000 ns,
  WHS +0.031 ns, and THS 0.000 ns with zero failed routes. It uses 13,105 LUTs,
  28,924 registers, 17 BRAM tiles, and 0 DSPs. Its bitstream SHA-256 is
  `d326353db16749c1f64178fd81cdef8c0469eb4665a4cf6500a609513827e0fc`.
- The first programmed image exposed an invalid M7 ACK IPv4 checksum. The ACK
  generator now uses the proven folded one's-complement calculation, and a new
  packet-level regression validates checksum `0xa571`, opcode `0x83`, and build
  ID `0x4d370001`. The corrected image passes M4 echo plus M7 STATUS/START/STOP.

The original medium/fast profile table incorrectly changed scaler register
`0x73` without its paired COM14 setting. Hardware reported error `0x0004` and
zero active bytes. The fixed table keeps the QVGA scaler pair at `0x19/0xF1`
and selects `CLKRC=0x01/0x00/0x40` for safe/medium/fast. Pages 13/14 read back
those exact values, and all three profiles report 640 active RGB565 bytes by
240 lines.

- Safe completed 1,000 grayscale and 1,000 Sobel frames at 7.503 FPS.
- Medium completed 1,000 grayscale and 1,000 Sobel frames at 15.006 FPS.
- Fast completed 1,000 grayscale and 1,000 Sobel frames at 30.012 FPS.
- Every session had zero host integrity errors and zero FPGA error flags; the
  final setup check also passed after returning the board to safe.

The first 1,000-frame synthetic hardware check exposed a live-camera input FIFO
overflow while the synthetic generator owned the core. Blocking live writes
removed error `0x2000`, but allowing the camera to resume immediately then
overwrote the synthetic frame interval before the host read it. The final RTL
holds live input until the next CONFIGURE or START and resumes only on camera
coordinate `(0,0)`. The expanded accelerated-core bench covers both the blocked
and explicit-resume cases. A second independent 200 MHz Sobel lane now processes
`lane0 ^ 0xA5`; the combined CRC proves both lanes and the aggregate per-frame
interval is 38,400 cycles (0.192 ms). The output-FIFO overflow indication is now
a core-domain sticky level followed by a two-flop synchronizer, and the remaining
CDC/DRC findings are classified in `milestone7_cdc_drc_classification.md`. The
final candidate still needs to be programmed and rerun because this execution
environment could not obtain external approval for Vivado hardware-manager
access after the board connected.

The FPGA/OpenCV comparison, threshold mode, dashboard, and activity-monitor
items remain open. Camera-profile qualification and CDC/DRC classification no
longer block those tasks.

## Features enabled by this foundation after M7

The M7 architecture should leave clean extension points for:

- host-programmable 3x3 convolution kernels;
- multiple regions of interest and per-region statistics generated in FPGA;
- edge-direction histograms, line/Hough detection, or simple lane guidance;
- event-triggered transmission to reduce bandwidth further;
- color overlays or side-by-side raw/processed diagnostics;
- remote dashboard access or a WebRTC gateway beyond the local Streamlit UI;
- lightweight compression, DDR frame buffering, or reliable frame transport;
- multi-stage filters such as blur, morphology, corner detection, or optical
  flow approximations;
- a small quantized classifier that consumes FPGA-produced features.

These are follow-on options, not M7 acceptance requirements. M7 should finish
with one polished use case and measured extension points rather than several
half-integrated demonstrations.
