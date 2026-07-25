# Milestone 7 benchmark result

Generated: `2026-07-25T18:13:28.237170+00:00`

| Measurement | Result |
|---|---:|
| OpenCV median kernel time | 0.070522 ms |
| FPGA median sustained frame time | 0.012288 ms |
| FPGA/OpenCV throughput ratio | 5.7391x |
| Bit-exact CRC agreement | True |
| 5% acceleration contract | PASS |

Kernel time, core time, transport FPS, and host CPU utilization are separate fields in the JSON/CSV.

## Live sessions

| Profile | Mode | Frames | FPS | CPU | Errors |
|---|---|---:|---:|---:|---:|
| safe | grayscale | 1000 | 7.5031 | 2.7% | 0 |
| safe | reference_sobel | 1000 | 7.5031 | 2.9% | 0 |
| safe | threshold | 1000 | 7.5031 | 2.4% | 0 |
| medium | grayscale | 1000 | 15.0062 | 5.4% | 0 |
| medium | reference_sobel | 1000 | 15.0062 | 5.8% | 0 |
| medium | threshold | 1000 | 15.0062 | 4.4% | 0 |
| fast | grayscale | 1000 | 30.0125 | 6.4% | 0 |
| fast | reference_sobel | 1000 | 30.0126 | 5.9% | 0 |
| fast | threshold | 1000 | 30.0146 | 5.5% | 0 |
