# Milestone 2 hardware validation

## Current status

The Milestone 2 RTL, golden-model checks, XSim regressions, synthesis, implementation, routing, timing signoff, and bitstream generation completed successfully on 2026-07-12. Physical programming and UART capture on the Arty A7 remain to be performed by the project owner, so hardware validation is not yet marked complete.

Generated bitstream:

```text
vivado_project/arty_conv.runs/impl_1/arty_m2_sobel_top.bit
```

## Board controls

- `BTN0`: reset.
- `BTN1`: start the selected 320x240 synthetic test.
- `SW0` through `SW2`: pattern number, binary 0 through 7.
- `LD4`: heartbeat.
- `LD5`: test source is running.
- `LD6`: completed test passed; sticky until another test or reset.
- `LD7`: completed test failed; sticky until another test or reset.
- `BTN2`, `BTN3`, and `SW3` are reserved for later controls.

Pattern numbers 5, 6, and 7 use the same coordinate-hash pattern.

| Pattern | Image | Expected CRC-32 |
|---:|---|---:|
| 0 | Black | `CB78A10B` |
| 1 | White | `CB78A10B` |
| 2 | Vertical edge | `18C9D29E` |
| 3 | Horizontal edge | `01A15B08` |
| 4 | 8x8 checkerboard | `0D9DA21C` |
| 5-7 | Coordinate hash | `E09929FA` |

Black and white intentionally have the same checksum because a constant image has a zero Sobel result everywhere.

## Validation procedure

1. Program `arty_m2_sobel_top.bit` onto the Arty A7.
2. Open the board USB-UART port at 115200 baud, 8 data bits, no parity, and one stop bit:

   ```text
   python scripts/python/serial_monitor.py --list
   python scripts/python/serial_monitor.py --port COM4 --output docs/milestone2_uart_capture.txt
   ```

3. Set `SW2:SW0` to pattern 0 and press `BTN1` once.
4. Confirm `LD5` lights briefly, then `LD6` becomes sticky and `LD7` remains off.
5. Confirm the UART line has 76,800 input pixels (`00012C00` hexadecimal), 75,684 output pixels (`000127A4` hexadecimal), the expected CRC, and `PASS`:

   ```text
   M2 PAT=0 IN=00012C00 OUT=000127A4 CRC=CB78A10B PASS
   ```

6. Repeat for patterns 1 through 5 and compare with the table above.
7. Press `BTN0` and confirm the pass/error LEDs clear.

After these checks pass, add the captured UART lines below and mark physical Milestone 2 validation complete.

## Physical results

- [x] Bitstream programmed successfully.
- [x] Heartbeat observed.
- [x] All six distinct built-in patterns reported the expected count and CRC.
- [x] `LD6` pass behavior confirmed.
- [x] Reset cleared sticky status.
- [x] UART capture saved under `docs/`.
