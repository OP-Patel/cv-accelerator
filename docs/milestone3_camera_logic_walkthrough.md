# Milestone 3 camera logic walkthrough

## Data path

```text
OV7670 DVP
  -> dvp_rgb565_capture (cam_pclk)
  -> xpm_fifo_async (cam_pclk to 100 MHz)
  -> camera_stream_adapter (RGB565 to grayscale)
  -> conv_pipeline_top (existing Sobel core)
  -> camera_debug_counters
  -> m3_uart_reporter
```

Every block has one job. Complete pixels cross the clock boundary as one 36-bit record: three markers, `x`, `y`, and RGB565. No data bit is synchronized independently.

## Clock and startup

`camera_xclk.sv` configures an Artix-7 MMCM for a 600 MHz VCO and divides it by 25, producing 24 MHz. A BUFG feeds an ODDR, which creates a 50% duty-cycle external clock. The camera remains powered down and in reset until MMCM lock plus a one-millisecond stable-clock interval.

## SCCB and identity

`sccb_master.sv` implements the transactions the camera needs: start, stop, three-byte register writes, the two-phase SCCB register read, ACK/NACK detection, and a transaction timeout. SDA is only driven low; a high is always a released bus.

`camera_register_init.sv` performs this readable sequence:

1. Write `COM7=0x80` for a soft reset.
2. Wait at least one millisecond.
3. Read `PID` and `VER`; require `PID=0x76` and `VER=0x70` or `0x73`.
4. Write 59 named configuration entries.
5. Wait 300 ms for the image controls to settle.

Any NACK, timeout, or identity mismatch stops initialization and leaves a sticky error.

## DVP capture and CDC

`dvp_rgb565_capture.sv` samples on rising `cam_pclk`. It accepts bytes only while HREF is high, stores the first byte, and emits a pixel after the second byte. X increments once per completed pixel; Y increments on HREF falling. A named byte-swap input supports first-hardware diagnosis without obscuring the normal order.

Sticky flags distinguish odd active-byte count, wrong line length, wrong frame height, and coordinates beyond 320x240. FIFO markers are attached to actual pixels: `(0,0)` is frame start, every `x=319` is line end, and `(319,239)` is frame end.

`camera_stream_cdc.sv` is a thin wrapper around `xpm_fifo_async`. The 1024-entry FIFO is continuously drained by the 100 MHz side. A full FIFO drops the arriving pixel, increments a count, and sets a sticky error.

## Grayscale, Sobel, and debug modes

`camera_stream_adapter.sv` reuses the bit-exact Milestone 2 RGB565 conversion and delays coordinates and markers by the same one-cycle latency.

`SW1=0` sends grayscale pixels into the existing Sobel pipeline. `SW1=1` is raw-camera mode: Sobel input is disabled and frame statistics finish at the last grayscale pixel. This isolates camera/configuration problems from convolution problems.

`camera_debug_counters.sv` snapshots stable per-frame counts and CRC-32 values. In Sobel mode it waits one cycle after the final `(318,238)` output so the last result is included.

## Board controls

| Control | Behavior |
|---|---|
| `BTN0` | global reset |
| `BTN1` | restart camera initialization |
| `BTN2` | clear sticky camera/FIFO errors |
| `BTN3` | request UART status immediately |
| `SW0` | sensor color bar at next initialization |
| `SW1` | raw grayscale mode (`1`) or Sobel mode (`0`) |
| `SW2` | RGB565 byte-order override |
| `SW3` | freeze the last frame statistics |
| `LD4` | heartbeat |
| `LD5` | initialization passed |
| `LD6` | stretched frame activity |
| `LD7` | any live sticky error |

UART lines use fixed-width hexadecimal fields:

```text
M3 ID=7673 CFG=P WR=0042 NACK=0000 F=0000002A LINE=00F0 PIX=00012C00 GRAY=12345678 OUT=000127A4 SOB=9ABCDEF0 ERR=0000 RAWB=0280 RAWL=00F0
```

`WR=0042` is 66 writes: one reset plus 65 table entries. The six added
entries explicitly set the QVGA hardware window observed to be necessary on
the physical `0x7673` sensor. `OUT` is the Sobel output count; `SOB` is its CRC.

For the deterministic software bars model, the expected 320x240 line is:

```text
PATTERN=bars LINE=00F0 PIX=00012C00 GRAY=4679D125 OUT=000127A4 SOB=F5D3DC76
```

This is a host-generated pattern. The physical OV7670 color-bar CRC must be recorded separately because its exact bar ordering and processing depend on the validated sensor configuration.
