# Milestone 1 hardware validation record

## Current evidence state

This revision contains the RTL, constraints, testbenches, build/report scripts, and serial monitor. Physical validation was reported successful by the project owner on 2026-07-11. The generated implementation report currently on disk predates the final UART XDC correction, so it should be regenerated before being treated as final archival evidence.

## Tool validation

- [x] Run both XSim testbenches with `scripts/run_simulations.tcl`.
- [x] Record the two `PASS:` lines and the Vivado version in `simulation_results_milestone1.txt`.
- [x] Run synthesis, implementation, and bitstream generation in Vivado 2026.1.
- [x] Confirm implementation completes without critical warnings relevant to clock, reset, unconstrained I/O, or multiple drivers.
- [x] Confirm the completed pre-XDC-correction run has positive estimated setup and hold slack (WNS 4.552 ns, WHS 0.118 ns).
- [ ] Regenerate final reports after the UART pin correction and record their final WNS/WHS.
- [ ] Commit `timing_summary_milestone1.rpt` and `utilization_milestone1.rpt` under `docs/`.

## Board observations

Board serial number: _pending_

Bitstream/programming date: 2026-07-11

Vivado version: 2026.1

- [x] Program the Arty A7-100T with the generated bitstream.
- [x] Observe `LD4` changing about every 0.671 seconds.
- [x] Hold `BTN0`; confirm all four single-color LEDs turn off.
- [x] Release `BTN0`; confirm the heartbeat restarts from its off phase.
- [x] Change `SW0` through `SW2`; confirm `LD5` through `LD7` follow after about 10 ms.
- [x] Change `SW3`; confirm the UART hexadecimal digit changes even though no dedicated LED remains for it.
- [x] Press each of `BTN1`, `BTN2`, and `BTN3`; confirm each new press requests a status line and holding a button does not continuously retrigger.

Heartbeat photo/video path or link: _pending_

Observed LED/reset notes: Project owner reports all physical LED, reset, switch, and button checks valid.

## Laptop serial observations

Port used: COM4

Command used: `python scripts/python/serial_monitor.py --port COM4 --duration 15`

Expected configuration: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control.

Expected line shape:

```text
M1 OK SW=0x0
M1 OK SW=0x5
M1 OK SW=0xF
```

- [x] Confirm the first line appears after reset release.
- [x] Confirm a line appears every five seconds.
- [x] Confirm the switch nibble follows the physical switch state.
- [x] Confirm manual button-triggered lines.
- [ ] Capture real output with `scripts/python/serial_monitor.py --port COMx --output docs/uart_terminal_milestone1.txt`.
- [ ] Review the capture for replacement characters, framing garbage, or missing line endings.

Observed UART notes: Project owner reports readable laptop-side output at 115200 8N1 on COM4.

Final hardware result: **PASS (user-attested 2026-07-11)**
