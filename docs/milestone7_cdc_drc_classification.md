# Milestone 7 CDC and DRC classification

## Signoff decision

Vivado 2026.1 reports no DRC errors and no routed timing failures. The CDC and
DRC reports still contain structural warnings because the design deliberately
uses asynchronous FIFOs, asynchronous-assert/synchronous-release resets, and
toggle-handshake status snapshots. These findings are classified below; none is
silently waived.

The final reports are:

- `artifacts/m7_runs/build/cdc_milestone7.rpt`;
- `artifacts/m7_runs/build/drc_milestone7.rpt`;
- `artifacts/m7_runs/build/timing_summary_milestone7.rpt`.

## CDC findings

| Finding | Count | Classification |
|---|---:|---|
| CDC-1 | 13 | Eight paths are internal XPM asynchronous-FIFO reset state, four are the inherited M4/M5 dual-clock Ethernet TX FIFO data path protected by Gray-pointer full/empty discipline, and one is `session_active` entering an `ASYNC_REG` two-flop synchronizer. The analyzer does not recognize these complete structures because their source registers use asynchronous reset. |
| CDC-3 | 30 | Accepted two- or three-flop single-bit synchronizers. This includes the final `clear_metrics`, registered synthetic-busy, and sticky output-overflow crossings. |
| CDC-5 | 3 | The three wide status buses are held in source-domain latches and sampled only after a request/acknowledge toggle handshake. The analyzer sees the bus flops but does not infer the surrounding coherency protocol. |
| CDC-6 | 17 | XPM FIFO Gray pointers and stable configuration/count buses paired with synchronized request toggles. Accepted as protocol-qualified multi-bit crossings. |
| CDC-10 | 5 | Reset paths into the camera, 24 MHz XCLK, 200 MHz core, RX, and TX reset synchronizers. Assertion is intentionally asynchronous; release is two-flop synchronized in each destination domain. |
| CDC-15 | 56 | Clock-enable-controlled reads in the inherited Ethernet FIFO and observational camera/UART status paths. Data is consumed only under the matching synchronized empty/valid, snapshot, or status-enable protocol. |

The M7 output-FIFO overflow indication was not merely classified. It was fixed:
the core-domain pulse now sets a sticky core-domain bit, that level crosses a
two-flop `ASYNC_REG` synchronizer, and only then sets the system-domain error
flag. Registering the synthetic-busy source before its synchronizer also removes
the former combinational-before-synchronizer finding.

## DRC findings

The post-route DRC report contains 42 warnings and zero errors:

| Rule | Count | Classification |
|---|---:|---|
| REQP-1839 | 20 | RAMB36 enable/control logic is driven by registers with asynchronous reset. Reset discards FIFO/frame-buffer contents by design; no memory contents are consumed across reset, and normal reset release is synchronized per clock domain. |
| REQP-1840 | 20 | The same reset-time condition on RAMB18 line buffers and FIFO storage. Contents are invalid while reset is active and are repopulated from a complete frame after release. |
| CHECK-3 | 2 | Report-limit notices for the two rules above, not two additional circuit problems. |

This classification is bounded to reset behavior. Any future feature that needs
to preserve RAM contents across reset must replace the affected asynchronous
control with a timed synchronous reset before relying on those contents.

## Evidence required after programming

The structural classification does not replace hardware validation. The final
bitstream must still pass M7 setup/health, the five-run synthetic benchmark,
all three 1,000-frame camera profiles, and the thresholded live stream with zero
FPGA or host integrity errors.
