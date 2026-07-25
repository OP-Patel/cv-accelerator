# Arty A7 real-time edge accelerator

An OV7670 camera feeds a timing-clean, 32-lane Sobel pipeline in an Arty
A7-100T. The FPGA converts RGB565 to grayscale, detects edges, packages the
result into integrity-checked UDP packets, and streams validated frames to a
guided Streamlit console.

```text
OV7670 → RGB565 capture → grayscale → 32-lane Sobel @ 200 MHz
       → M5CV/UDP packetizer → strict host reassembly → live view/events
```

## The result

The completed physical acceptance run measured the FPGA at **5.739× the
throughput of single-thread OpenCV** on the same deterministic 320×240 inputs.
Both implementations produced the same combined output CRC.

| Accepted measurement | Result |
|---|---:|
| FPGA sustained frame time | **0.012288 ms** |
| FPGA sustained compute throughput | **81,380 frames/s** |
| OpenCV median kernel time | **0.070522 ms** |
| OpenCV median compute throughput | **14,180 frames/s** |
| FPGA / OpenCV throughput | **5.739×** |
| Core-time reduction | **82.6%** |
| Bit-exact combined CRC | **`0x9e562313` — match** |
| Live frames checked | **9,000** |
| Missing/duplicate/reordered/malformed/CRC/sequence errors | **0** |

This is a controlled Sobel-kernel comparison, not a claim about every possible
computer-vision workload. FPGA core time, camera rate, Ethernet transport, and
host display rate are reported separately. The live camera is sensor-limited
to the selected 7.5, 15, or 30 FPS profile; the accelerator has substantially
more compute headroom than the camera requires.

The complete accepted evidence is in:

- [`docs/m7_benchmark_results.json`](docs/m7_benchmark_results.json)
- [`docs/m7_benchmark_results.csv`](docs/m7_benchmark_results.csv)
- [`docs/milestone7_benchmark_results.md`](docs/milestone7_benchmark_results.md)
- [`docs/milestone7_timing_summary_pass.rpt`](docs/milestone7_timing_summary_pass.rpt)

## Start with the GUI

The M7 console is the normal way to operate the project. It programs the
verified image, checks the board, controls the live stream, runs acceptance,
shows saved results, and explains the compute and packet path.

1. Install the host dependencies once:

   ```powershell
   py -3 -m pip install -r scripts/python/requirements-m7.txt
   ```

2. Double-click [`Launch_M7_Dashboard.cmd`](Launch_M7_Dashboard.cmd).

The browser opens to the local Streamlit app. No benchmark, packet-receiver, or
Vivado command needs to be typed after that. The terminal fallback is:

```powershell
.\scripts\run_m7_dashboard.ps1
```

The console has five work areas:

| Area | What it does |
|---|---|
| **1 · Setup** | Checks dependencies and IPv4, programs the verified bitstream, explains switches/LEDs, and runs the FPGA health check |
| **2 · Live** | Applies safe/medium/fast camera profiles, displays validated frames, watches integrity counters, and creates activity events |
| **3 · Benchmark** | Runs a quick shakedown or full 5×1,000 acceptance plus the physical 3×3 profile/mode matrix |
| **Proof** | Makes the speed result, CRC match, live FPS, host CPU, and zero-error matrix explicit and downloadable |
| **How it works** | Animates one Sobel computation and provides a click-to-explore UDP packet/reassembly exhibit |

## Hardware setup

Required hardware:

- Digilent Arty A7-100T (`xc7a100tcsg324-1`)
- direct-DVP OV7670 module
- USB cable for power, JTAG programming, and UART
- Ethernet cable to the validation computer
- the tested ASIX USB Ethernet adapter, or another adapter configured the same
  way

Wire the camera exactly as documented in
[`docs/milestone3_camera_hardware_contract.md`](docs/milestone3_camera_hardware_contract.md).
Power the board down before moving camera wiring.

Configure the direct Windows Ethernet adapter:

```text
Computer IPv4: 192.168.10.1
Subnet mask:   255.255.255.0
Gateway:       blank
FPGA IPv4:     192.168.10.2
FPGA MAC:      02:00:00:00:00:01
```

The dashboard detects whether `192.168.10.1` is assigned and shows the exact
one-time Windows command if it is missing.

### Switches

Use this normal dashboard position:

```text
SW0 = 0 for the live lens, or 1 for OV7670 color bars
SW1 = 0
SW2 = 1
SW3 = 0
```

| Control | Exact M7 function |
|---|---|
| `SW0` | Camera source on the next initialization: `0` live lens, `1` internal color bars |
| `SW1` | Grayscale override: `0` lets the GUI select grayscale/Sobel; `1` forces grayscale |
| `SW2` | Local streaming gate: must be `1` for camera packets; `0` is a hard inhibit |
| `SW3` | Reserved and unused by the M7 RTL; leave at `0` |

Changing `SW0` does not immediately reprogram the sensor. Press `BTN1`, or use a
dashboard configuration action that restarts camera initialization.

### Buttons and LEDs

| Control | Meaning |
|---|---|
| `BTN0` | Full design reset |
| `BTN1` | Restart camera initialization and Ethernet PHY discovery |
| `BTN2` | Clear sticky errors and counters |
| `BTN3` | Print one coherent UART status report |
| `LD4` | Heartbeat; should blink whenever the design is alive |
| `LD5` | Camera configured, camera ID valid, and Ethernet link/identity valid |
| `LD6` | Camera packet activity; visible during live transport, not necessarily during the very short synthetic compute test |
| `LD7` | Any combined sticky error; should remain off |

If `LD7` turns on, stop the stream, correct the physical cause, press `BTN2` to
clear flags, press `BTN1` to reinitialize, and run **FPGA health check** again.

## Program the correct M7 image

The dashboard’s **Program verified bitstream** button calls Vivado 2026.1 in
batch mode and checks that exactly one A7-100T is attached.

Verified image:

```text
artifacts/m7_runs/build/arty_m7_camera_ethernet_top.bit
```

```text
SHA-256 0fb90997a1765c921955a383959c1cba94410ff54119dac3a46bf799a80689b6
Size     3,826,007 bytes
```

Generated Vivado mirror:

```text
vivado_project_m7/arty_conv_m7.runs/impl_1/arty_m7_camera_ethernet_top.bit
```

To inspect the implemented design manually:

```powershell
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  "C:\Users\Om Patel\Desktop\arty-conv-accelerator\vivado_project_m7\arty_conv_m7.xpr"
```

Do not select an M5/M6 bitstream. A stale image will answer older protocol
commands but cannot acknowledge M7 opcode 3 status requests.

## What the three processing modes mean

### Grayscale diagnostic

RGB565 stores red, green, and blue in 16 bits. The FPGA combines those channels
into one 8-bit brightness value. Grayscale is useful because it:

- verifies the camera, capture timing, pixel order, and UDP transport before
  edge processing complicates the picture;
- supplies the exact input used by the OpenCV control;
- removes color information that Sobel does not need.

### Reference Sobel

Sobel evaluates a 3×3 neighborhood around every interior pixel. Two kernels
measure horizontal and vertical brightness change:

```text
Gx                  Gy
-1  0  +1           +1  +2  +1
-2  0  +2            0   0   0
-1  0  +1           -1  -2  -1
```

The project computes `min(255, |Gx| + |Gy|)`. Flat regions approach zero;
strong boundaries approach 255. A 320×240 input produces a 318×238 Sobel image
because a complete 3×3 neighborhood does not exist at the outer border.

### Thresholded Sobel

Thresholding keeps edge values at or above a chosen magnitude and suppresses
weaker responses. It turns a detailed edge-strength image into a cheaper
decision signal for contours, motion regions, occupancy, or event triggers.

Whether the camera sees an obvious edge does **not** affect packet correctness
or benchmark validity. A high-contrast target only makes the Sobel output
easier for a person to recognize. The controlled compute benchmark uses 32
deterministic patterns so both FPGA and OpenCV receive identical work.

## Why the FPGA is faster here

OpenCV executes the Sobel operations as instructions on general-purpose CPU
cores. The M7 design turns the algorithm into physical dataflow:

1. BRAM line buffers keep two previous image rows next to the arithmetic.
2. Shift registers form each 3×3 window without rereading a full frame.
3. Dedicated adders compute `Gx` and `Gy` in parallel.
4. Saturation and optional thresholding are pipeline stages, not software
   branches.
5. Thirty-two independent synthetic lanes operate at 200 MHz for the controlled
   benchmark.
6. Counters and a combined CRC are read directly from the FPGA to prove both
   time and output identity.

After the pipeline fills, pixels continue moving deterministically without
operating-system scheduling. In a real camera system that means the CPU can
spend its time on tracking, decisions, storage, networking, or the user
interface instead of repeating local pixel arithmetic.

Sobel itself is a building block, not a complete vision application. The same
line-rate architecture is useful in robotics, industrial inspection, smart
cameras, document scanning, lane/contour extraction, and as a front end to more
expensive algorithms.

## UDP packet and validation contract

One full payload packet contains:

```text
Ethernet 14 B | IPv4 20 B | UDP 8 B | M5CV header 32 B
| pixel payload up to 1,024 B | Ethernet FCS 4 B
```

The 32-byte `M5CV` header carries:

- magic/version and stream mode;
- first, last, and discontinuity flags;
- frame sequence and packet index/count;
- pixel offset and payload length;
- frame width/height;
- a CRC32 for the pixel payload.

The host rejects a packet or frame if dimensions, count, order, offsets, flags,
length, CRC, or frame sequence are inconsistent. Grayscale frames contain
76,800 bytes in 75 packets. Sobel frames contain 75,684 bytes in 74 packets;
the final packet carries 932 pixels.

UDP keeps the FPGA transport small and deterministic. The application header
adds the evidence required to distinguish “a datagram arrived” from “this
complete video frame is correct.”

## Benchmark methodology

Full acceptance performs:

1. five independent OpenCV runs of 1,000 deterministic frames;
2. five physical FPGA synthetic runs of 1,000 frames;
3. combined output CRC comparison;
4. safe, medium, and fast live camera sessions;
5. grayscale, reference Sobel, and thresholded Sobel in every profile;
6. 1,000 validated live frames in every profile/mode cell.

The accepted live matrix:

| Profile | Grayscale | Reference Sobel | Thresholded Sobel | Frames | Errors |
|---|---:|---:|---:|---:|---:|
| safe | 7.5031 FPS | 7.5031 FPS | 7.5031 FPS | 3,000 | 0 |
| medium | 15.0062 FPS | 15.0062 FPS | 15.0062 FPS | 3,000 | 0 |
| fast | 30.0125 FPS | 30.0126 FPS | 30.0146 FPS | 3,000 | 0 |

The first frame after each deliberate STOP/START is marked as a discontinuity.
That expected session-boundary marker is tracked separately and is not an
integrity error.

Dashboard-launched results are saved under:

```text
artifacts/m7_runs/YYYYMMDD_HHMMSS/
  results.json
  results.csv
  results.md
  console.log
```

The **Proof** tab always opens the newest parseable result and provides download
buttons.

## Implementation status

| Property | Routed M7 result |
|---|---:|
| Target | Arty A7-100T / `xc7a100tcsg324-1` |
| Synthetic lanes | 32 |
| Accelerator clock | 200 MHz |
| WNS / TNS | +0.030 ns / 0 ns |
| WHS / THS | +0.024 ns / 0 ns |
| LUTs | 17,731 / 63,400 (27.97%) |
| Registers | 35,303 / 126,800 (27.84%) |
| BRAM tiles | 47 / 135 (34.81%) |
| DSP blocks | 0 |

All M7 RTL testbenches and host tests pass. The routed bitstream completed full
physical acceptance on July 25, 2026.

## Developer entry points

The GUI is preferred for normal use. The underlying tools remain independently
runnable for development and CI:

```powershell
# Host tests
py -3 -m unittest discover -s scripts/python -p "test_*.py"

# M7 RTL testbenches
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  -mode batch -source scripts/run_m7_simulations.tcl

# Rebuild implementation and bitstream
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  -mode batch -source scripts/build_m7_bitstream.tcl
```

Key source areas:

```text
rtl/conv/                         grayscale, Sobel, accelerated pipeline
rtl/camera/                       OV7670 clock, SCCB initialization, capture
rtl/integration/                  control receiver, stream FIFO, packetizer
rtl/ethernet/                     MII, ARP/IPv4/UDP, CRC/FCS
rtl/top/arty_m7_camera_ethernet_top.sv
scripts/python/m7_dashboard.py    guided operator console
scripts/python/m7_showcase.py     interactive computation/packet exhibits
scripts/python/benchmark_m7.py    acceptance runner
```
