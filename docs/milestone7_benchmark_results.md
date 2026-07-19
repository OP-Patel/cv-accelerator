# Milestone 7 benchmark results

## Status

No physical M7 benchmark was run because the Arty A7 and Ethernet adapter were
not attached. This is deliberate: the implementation is being validated by
host tests and RTL/synthesis evidence first, and the board-dependent numbers
will be filled in during the hardware handoff.

The authoritative command is:

```powershell
py -3 scripts/python/benchmark_m7.py --quick
```

For acceptance, omit `--quick` and use the optional live matrix only after the
board is connected:

```powershell
py -3 scripts/python/benchmark_m7.py --live
```

Each run writes JSON, CSV, and Markdown. The result schema keeps these
quantities separate:

- single-thread OpenCV kernel time (mean, median, p95, min, max, standard
  deviation, and sample count);
- FPGA measured synthetic core interval and first-input-to-last-output cycles;
- transport and live inter-frame FPS;
- request-to-first-frame time and host CPU metadata;
- packet/frame/FIFO/camera error counters;
- bit-exact CRC agreement and the 1.05x FPGA/OpenCV throughput contract.

The benchmark never labels `pixels / requested_clock` as end-to-end FPS. A
camera profile may cap both live paths even when the isolated synthetic core
comparison wins.

## Current validation evidence

```text
python scripts/python/run_m7_host_tests.py
Ran 10 tests ... OK
```

The OpenCV-only M6 baseline remains the comparison reference until a fresh
five-run M7 measurement is captured:

```text
M6 controlled OpenCV mean:   0.629 ms
M6 controlled OpenCV median: 0.504 ms
M6 physical stream cadence:  7.503 FPS
```

Those are historical M6 values, not M7 results. A successful M7 report must
replace them with fresh measurements and include the exact Python, NumPy,
OpenCV, CPU, operating-system, thread-count, and FPGA build metadata.
