# Milestone 7 benchmark result

> Superseded diagnostic run. This result came from the earlier single-lane
> 76,800-cycle FPGA image and intentionally records why it missed the 1.05x
> contract. The final dual-lane bitstream reports 38,400 cycles per frame, but
> its five-run hardware result has not been generated yet. Re-running
> `scripts/python/benchmark_m7.py` after programming the final image overwrites
> this Markdown plus the matching JSON/CSV artifacts.

Generated: `2026-07-19T20:14:47.935917+00:00`

| Measurement | Result |
|---|---:|
| OpenCV median kernel time | 0.283500 ms |
| FPGA median sustained frame time | 0.384000 ms |
| FPGA/OpenCV throughput ratio | 0.7383x |
| Bit-exact CRC agreement | True |
| 5% acceleration contract | FAIL |

Kernel time, core time, transport FPS, and host CPU utilization are separate fields in the JSON/CSV.
