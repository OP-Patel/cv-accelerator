# Milestone 1 hardware validation record

## Current evidence state

This revision contains the RTL, constraints, testbenches, build/report scripts, and serial monitor. Physical validation has **not yet been recorded**. Do not mark Milestone 1 complete until the observations below are filled with real board results and the generated timing/utilization reports are present.

## Tool validation

- [x] Run both XSim testbenches with `scripts/run_simulations.tcl`.
- [x] Record the two `PASS:` lines and the Vivado version in `simulation_results_milestone1.txt`.
- [ ] Run `scripts/build_bitstream.tcl`.
- [ ] Confirm implementation completes without critical warnings relevant to clock, reset, unconstrained I/O, or multiple drivers.
- [ ] Confirm the timing summary reports all constraints met and record worst setup/hold slack.
- [ ] Commit `timing_summary_milestone1.rpt` and `utilization_milestone1.rpt` under `docs/`.

## Board observations

Board serial number: _pending_

Bitstream/programming date: _pending_

Vivado version: _pending_

- [ ] Program the Arty A7-100T with the generated bitstream.
- [ ] Observe `LD4` changing about every 0.671 seconds.
- [ ] Hold `BTN0`; confirm all four single-color LEDs turn off.
- [ ] Release `BTN0`; confirm the heartbeat restarts from its off phase.
- [ ] Change `SW0` through `SW2`; confirm `LD5` through `LD7` follow after about 10 ms.
- [ ] Change `SW3`; confirm the UART hexadecimal digit changes even though no dedicated LED remains for it.
- [ ] Press each of `BTN1`, `BTN2`, and `BTN3`; confirm each new press requests a status line and holding a button does not continuously retrigger.

Heartbeat photo/video path or link: _pending_

Observed LED/reset notes: _pending_

## Laptop serial observations

Port used: _pending_

Command used: _pending_

Expected configuration: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control.

Expected line shape:

```text
M1 OK SW=0x0
M1 OK SW=0x5
M1 OK SW=0xF
```

- [ ] Confirm the first line appears after reset release.
- [ ] Confirm a line appears every five seconds.
- [ ] Confirm the switch nibble matches all 16 switch combinations, or at minimum 0, 5, A, and F.
- [ ] Confirm manual button-triggered lines.
- [ ] Capture real output with `scripts/python/serial_monitor.py --port COMx --output docs/uart_terminal_milestone1.txt`.
- [ ] Review the capture for replacement characters, framing garbage, or missing line endings.

Observed UART notes: _pending_

Final hardware result: **PENDING**
