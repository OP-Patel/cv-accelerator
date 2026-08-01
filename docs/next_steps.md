# Future work and feasibility analysis

The hardware platform is complete. It captures a real OV7670 stream, performs
fixed-point vision in custom RTL, transports validated pixels over a custom
Ethernet/UDP contract, and has passed the controlled compute and live-path
acceptance runs.

The remaining work is no longer “make Sobel work.” It is to choose an outcome,
measure that outcome in a real scene, and package the evidence. A neural network
is one possible continuation, not a prerequisite for completing the project.

## Executive recommendation

Complete the application-level activity detector first, evaluate a small model
on the host second, and only then decide whether FPGA CNN integration is
justified.

| Option | Feasibility on the current repository | Technical relevance | Recommendation |
|---|---|---|---|
| Thresholded-Sobel activity detector | High: camera, threshold mode, ROI monitor, event logging and 30 FPS transport already exist | High: converts the verified platform into a measured application | **Do next** |
| PyTorch CNN on the host | High: no RTL or bitstream change; uses the current validated frame stream | Medium/high: establishes whether learning improves the decision and creates a reusable dataset | **Do after the use-case baseline** |
| Quantized CNN in Artix-7 fabric | Medium/low: plausible resource budget, but requires a new compiler flow, stream adapter, quantization study and full physical requalification | High if the goal is FPGA-ML integration; lower if it replaces clear custom RTL with an unvalidated generated block | **Proceed only if the host study shows a material benefit** |

For a recruiter or senior hardware reviewer, a smaller system with a defined
application, explicit timing boundaries, repeatable measurements and known
limitations is stronger than adding a generic CNN without an accuracy or
latency requirement. The FPGA-CNN path is valuable when it answers a measured
need—not as a replacement for the existing RTL solely because CNNs are more
complex.

## Recommended definition of complete

Turn the existing thresholded-Sobel and activity-monitor path into a
**doorway or workcell activity detector**:

```text
camera → FPGA grayscale/Sobel/threshold → validated UDP frame
       → fixed region of interest → activity transition → event log/snapshot
```

This is the strongest immediate use case because every technical dependency is
already present. It demonstrates why preprocessing at the sensor edge matters
without introducing a new compiler, memory system, or model before the current
system has an application-level result.

### Use-case experiment

1. Mount the camera so the framing and lighting are repeatable.
2. Define one fixed region of interest in the live console.
3. Record labelled sessions containing:
   - empty scene;
   - person/object enters;
   - person/object exits;
   - movement outside the region;
   - lighting change;
   - camera bump or partial occlusion.
4. Tune the edge threshold, trigger score, clear score, and hold frames only on
   a training subset.
5. Freeze those values and run a held-out acceptance sequence.
6. Export the activity CSV, event log, representative input/output frames,
   benchmark JSON, and a short demonstration video.

### Application acceptance gate

| Requirement | Suggested gate |
|---|---:|
| Positive transitions | At least 20 held-out events |
| Event recall | At least 95% |
| False events | At most 1 per 10 minutes |
| Event latency | Report median and p95 at the 30 FPS profile |
| Link integrity | 0 missing/duplicate/reordered/malformed/CRC/sequence errors |
| Host CPU | Reported, not mixed with FPGA core time |
| Evidence | CSV + JSON + screenshots + test protocol + demo video |

These are project targets, not results that have already been measured.

## Three continuation tracks

| Track | What changes | What it proves | Risk |
|---|---|---|---|
| A. Productize current logic | Complete the activity use case; optionally move ROI scoring and event packets into RTL | A real edge appliance with deterministic preprocessing and networking | Low |
| B. Hybrid PyTorch CNN | Keep FPGA preprocessing; run a small classifier on the host | Whether learned inference adds accuracy without destabilizing the hardware platform | Medium |
| C. Quantized CNN in FPGA fabric | Train, quantize, compile, integrate, route, and physically validate a network IP block | True learned inference in programmable logic | High |

Track A should be completed first. Track B creates the dataset and model evidence
needed to justify Track C.

## Track B: add a PyTorch model without changing RTL

PyTorch does not run inside the Artix-7 fabric. In the hybrid version, PyTorch
trains the model and a host runtime performs inference on frames received from
the existing FPGA.

### Suggested first model

Use a fixed `64×64` grayscale or thresholded-edge crop and a deliberately small
network:

```text
1×64×64 input
→ 3×3 convolution, 8 channels
→ ReLU + 2×2 pooling
→ 3×3 convolution, 16 channels
→ ReLU + 2×2 pooling
→ fixed global/average pooling
→ 2–4 output classes
```

Good first labels are `empty` / `occupied`, or `idle` / `activity`. Avoid a
large generic dataset: capture from this exact OV7670 path so the train and test
images contain the real sensor noise, exposure, crop, optics, and FPGA
preprocessing.

Run an ablation with the same splits:

| Input | Question |
|---|---|
| Grayscale | How much can the model learn from the original luminance image? |
| Reference Sobel | Does fixed FPGA preprocessing retain enough information? |
| Thresholded Sobel | Can a cheaper binary representation preserve the decision? |

Report accuracy, precision/recall, confusion matrix, per-frame host inference
time, total host CPU, and end-to-end latency. This determines whether an FPGA
CNN is worth the additional implementation cost.

## Track C: put a quantized CNN in the FPGA

The realistic flow is:

```text
PyTorch/Brevitas quantization-aware training
→ QONNX export
→ FINN or hls4ml conversion
→ streaming FPGA IP
→ manual Vivado integration
→ RTL/software equivalence
→ routed timing
→ physical camera acceptance
```

[FINN](https://finn.readthedocs.io/en/latest/getting_started.html) is the most
natural match for a very low-precision, streaming network. Its documented flow
trains a quantized network with Brevitas, exports QONNX, and generates a
dataflow-style accelerator. FINN can emit stitched AXI-stream IP for any AMD
Xilinx FPGA, but its automatic bitstream/driver shells target a limited set of
PYNQ-class boards. The Arty A7 therefore needs manual integration into this
repository's Vivado design.

[hls4ml](https://fastmachinelearning.org/hls4ml/intro/introduction.html) is a
second option. It converts supported PyTorch/ONNX/Keras models into HLS IP and
lets the designer trade resource use against latency. Its documentation notes
that the direct PyTorch frontend is still less mature than the Keras paths;
quantized Brevitas models currently go through QONNX rather than direct
ingestion. For a new AMD/Xilinx project, its documentation recommends the Vitis
backend.

PyTorch can also export a regular model to ONNX with
[`torch.onnx.export`](https://docs.pytorch.org/docs/stable/onnx.html), but a
regular ONNX graph is not automatically a practical FPGA implementation. The
network still needs supported operators, fixed tensor shapes, deliberate
quantization, folding, and a hardware generation flow.

### Toolchain compatibility risk

The current project is implemented with Vivado 2026.1 on Windows. That is newer
than the tool combinations documented by the candidate ML flows:

- FINN's current [getting-started documentation](https://finn.readthedocs.io/en/latest/getting_started.html)
  describes a Docker/Linux flow using Vivado/Vitis 2022.2 and provides automatic
  system integration only for its supported PYNQ/Alveo targets. An Arty A7 build
  receives stitched AXI-stream IP, not a ready-to-program board image.
- hls4ml's [supported-tool table](https://fastmachinelearning.org/hls4ml/intro/status.html)
  lists Vitis HLS 2022.2–2024.1 in its tested range. Its
  [PyTorch frontend documentation](https://fastmachinelearning.org/hls4ml/frontend/pytorch.html)
  says that frontend is still less mature than the Keras paths and that
  Brevitas models currently enter through QONNX.

Therefore, “install FINN and rebuild this repository” is not a low-risk step.
Use an isolated, documented Linux/Docker or WSL environment to generate and
functionally verify IP. Record the exact compiler and Vivado/Vitis versions.
Only then import the generated block into a separate M8 Vivado project. Do not
replace or upgrade the accepted M7 environment until the IP handoff has been
proven compatible.

### Why a tiny quantized network is realistic here

The routed M7 image currently uses:

| Resource | Used | Device | Unallocated before a CNN |
|---|---:|---:|---:|
| LUT | 17,731 | 63,400 | 45,669 |
| Registers | 35,303 | 126,800 | 91,497 |
| BRAM tiles | 47 | 135 | 88 |
| DSP48 | 0 | 240 | 240 |

This is useful headroom, especially because the existing Sobel implementation
uses no DSP blocks. It is not a fit guarantee. CNN topology, activation storage,
parallelism, stream adapters, routing congestion, and clock choice determine
whether the complete design closes timing.

The M7 resource figure includes 32 synthetic Sobel lanes used only by the
controlled benchmark. A CNN build should make an explicit choice:

- retain the M7 test core and fit the CNN in the remaining fabric, preserving
  the original comparison inside one image; or
- create a separate compile-time M8 configuration that reduces/removes the 31
  synthetic-only lanes and reallocates those resources to inference.

The second option is more likely to fit a useful network, but it must retain M7
as the immutable regression baseline. Resource numbers from the two builds
must not be mixed.

The board also includes 256 MB DDR3L, according to the
[Digilent Arty A7-100T product documentation](https://digilent.com/shop/arty-a7-100t-artix-7-fpga-development-board/),
but this project does not currently instantiate a DDR controller. A small
streaming network should first keep weights and intermediate storage in BRAM.
Adding MIG/DDR is a separate systems milestone and should be justified by an
actual feature-map requirement.

At the current maximum live rate, one 320×240 byte-per-pixel stream contains
`2,304,000` payload bytes/s before headers (about `18.4 Mbit/s`). That is well
below a 100 Mbit/s link, so the existing Ethernet path is adequate for dataset
capture and host inference. The primary CNN constraints are model storage,
feature-map buffering, generated-IP integration and timing—not the present live
pixel payload rate.

### Hardware integration plan

1. **Freeze the model contract**
   - fixed input size and channel count;
   - fixed integer/quantized representation;
   - fixed class order and output scale;
   - frozen validation tensors and expected logits/classes.
2. **Generate estimates before IP**
   - choose a conservative initial clock, such as 100 MHz;
   - vary FINN folding or hls4ml reuse factor;
   - reserve fabric for the existing camera, Ethernet, FIFO, and control logic;
   - reject candidates that only fit at near-100% utilization.
3. **Create a stream boundary**
   - crop/decimate the live 320×240 input to the model's fixed shape;
   - convert the current `valid/x/y/pixel` contract to AXI-stream or the chosen
     generated-IP protocol;
   - preserve frame boundaries across backpressure;
   - decide whether the original image stream and inference result run in
     parallel or in separate diagnostic modes.
4. **Define an inference result packet**
   - add a versioned `M7EV`-style event payload containing frame sequence,
     class ID, quantized score, model ID/hash, and CRC;
   - retain `M5CV` image packets for debugging and dataset capture.
5. **Verify layer by layer**
   - PyTorch float output;
   - quantized PyTorch/Brevitas output;
   - exported QONNX/ONNX output;
   - C++/HLS simulation;
   - RTL simulation;
   - integrated FPGA output for the same frozen tensors.
6. **Re-run the hardware contract**
   - timing clean with non-negative WNS/WHS;
   - no CDC/DRC regressions;
   - model accuracy within the frozen tolerance;
   - at least 30 live inferences/s;
   - zero stream or packet integrity errors;
   - end-to-end latency and resource/power evidence reported separately.

### CNN acceptance gate

| Requirement | Suggested first target |
|---|---:|
| Quantized accuracy loss vs float model | No more than 2 percentage points |
| Integrated output agreement | Exact class, bounded quantized-score tolerance |
| Live rate | At least 30 inferences/s |
| End-to-end latency | Less than one 30 FPS frame period (33.3 ms) |
| Timing | WNS and WHS non-negative |
| Stream integrity | 0 errors in a 1,000-frame run |
| Resource margin | Keep explicit post-route margin; do not accept estimate-only fit |

## Other work that strengthens the finished project

These items are independent of a CNN and improve reproducibility:

- complete the remaining dashboard setup/stop/cancel/export acceptance checks;
- complete the visible activity transition demonstration and archive its CSV;
- capture an annotated board/camera/Ethernet bench photograph;
- replace the unbranded camera module or document measured I/O levels and add
  level translation for a product-safe design;
- add a one-command demo recording procedure and a short architecture video;
- optionally program the verified image into Quad-SPI flash for standalone
  power-up instead of relying on JTAG after every reconfiguration;
- keep the existing M7 bitstream and benchmark corpus as a regression baseline
  before creating an M8 CNN branch.

## Recommended milestone order

```text
M8A  use-case protocol + labelled activity acceptance
M8B  dataset capture + hybrid PyTorch baseline
M8C  quantization study + FINN/hls4ml resource estimates
M9   streaming CNN IP integration (only if M8C is justified)
M10  routed, physical, application-level CNN acceptance
```

Reprogramming the connected board is not required for the documentation and UI
work in this revision. It will be required to operate the current live demo
after a stale image, and again after any future RTL or CNN integration changes.

## Research references

Primary sources reviewed for this feasibility assessment on July 31, 2026:

- AMD Research, [FINN getting started and supported FPGA hardware](https://finn.readthedocs.io/en/latest/getting_started.html)
- AMD Research, [FINN command-line build outputs and stitched IP](https://finn.readthedocs.io/en/latest/command_line.html)
- AMD Research, [FINN hardware build and deployment](https://finn.readthedocs.io/en/latest/hw_build.html)
- hls4ml, [status, supported frontends, layers and tool versions](https://fastmachinelearning.org/hls4ml/intro/status.html)
- hls4ml, [PyTorch and Brevitas frontend limitations](https://fastmachinelearning.org/hls4ml/frontend/pytorch.html)
- hls4ml, [Vivado/Vitis backend guidance](https://fastmachinelearning.org/hls4ml/backend/vitis.html)
- PyTorch, [`torch.onnx` export documentation](https://docs.pytorch.org/docs/stable/onnx.html)
- Digilent, [Arty A7-100T board resources and DDR3L](https://digilent.com/shop/arty-a7-100t-artix-7-fpga-development-board/)
- Project evidence: [`milestone7_hardware_validation.md`](milestone7_hardware_validation.md),
  [`milestone7_algorithm_evaluation.md`](milestone7_algorithm_evaluation.md), and
  [`m7_benchmark_results.json`](m7_benchmark_results.json)
