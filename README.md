# Arty A7-100T Real-Time Streaming Convolution Accelerator

## Setup

1. Install Vivado + Digilent Arty A7-100T board files.
2. From `scripts/`, run: vivado -mode batch -source create_project.tcl

3. Open `vivado_project/arty_conv.xpr` in the Vivado GUI, or continue headless with `build_bitstream.tcl`.

## Status

- [ ] Milestone 1: Minimal board bring-up
- [ ] Milestone 2: Core convolution datapath
- [ ] Milestone 3: Camera bring-up
- [ ] Milestone 4: Ethernet bring-up
- [ ] Milestone 5: Full integration