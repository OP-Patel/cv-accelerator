# Milestone 3 camera bring-up debugging postmortem

## Outcome

Milestone 3 passed functional hardware validation on July 14, 2026. The final
run configured the physical camera and processed frames 1 through 306 with
complete counts, stable checksums, and `ERR=0000`.

The bring-up was not a straight line. It exposed four different problems that
looked similar when reduced to a single `FAIL` label. The useful lesson was to
turn each failure into a measurement before changing the hardware or RTL.

## 1. Starting with an unknown module

The camera was an unbranded 18-pin OV7670 breakout with no schematic or part
number. Front and back photographs gave us the printed labels and showed two
small regulator circuits, but could not prove the internal I/O voltage or
whether level translation was present.

We transcribed the connector exactly as printed, mapped each signal to the
Arty's JB and JC Pmod pins, and kept the electrical uncertainty explicit in the
hardware contract. This prevented the connector orientation from becoming an
unrecorded assumption.

## 2. SCCB initially returned no identity

The first UART result was:

```text
[FAIL:ID,CFG,NACK,ERR] M3 ID=0000 CFG=F WR=0000 NACK=0001 ... ERR=0003
```

This meant the first SCCB transaction was not acknowledged. It did not mean
the DVP bus was wired incorrectly because no pixel transaction had occurred
yet. Resetting the FPGA and manually pressing `BTN1` restarted camera
initialization. A later attempt returned a real identity with no NACK:

```text
[FAIL:ID,CFG,ERR] M3 ID=7673 CFG=F WR=0001 NACK=0000 ...
```

That line proved power, XCLK, reset/power-down control, SCCB clock, SCCB data,
and the camera address were all working. It also exposed the next problem.

## 3. The physical revision reported `0x7673`

The original acceptance check expected the supplied older-datasheet identity
`0x7670`. The physical device repeatedly returned `PID=0x76`, `VER=0x73`.
Because the product byte was correct, the reads were repeatable, and NACK was
zero, this was treated as a supported OV7670 revision rather than as random
bus data.

The identity gate was changed to accept exactly `0x7670` or `0x7673`. It still
rejects other product IDs and unrelated version values. The register-init test
was extended to cover both accepted identities and an explicit mismatch.

After that change, all original configuration writes completed:

```text
[PASS:PASS] M3 ID=7673 CFG=P WR=003C NACK=0000 ... ERR=0000
```

The camera control path now passed, but no complete frame passed.

## 4. `ERR=0118` was a framing measurement, not a wiring verdict

The next status was:

```text
[FAIL:ERR] M3 ID=7673 CFG=P WR=003C NACK=0000 F=00000000 ... ERR=0118
```

The relevant sticky bits were:

| Bit | Value | Meaning |
|---:|---:|---|
| 3 | `0x0008` | active line did not contain exactly 640 bytes |
| 4 | `0x0010` | frame did not contain exactly 240 complete lines |
| 8 | `0x0100` | the downstream raster coordinates were discontinuous |

Those three flags can cascade from one bad width. A short line prevents a
320-pixel row, which then breaks both the frame count and downstream coordinate
sequence. Changing three subsystems at once would have hidden the root cause.

We added two raw camera-domain diagnostics to the UART line:

- `RAWB`: bytes observed during the most recently completed HREF interval;
- `RAWL`: HREF intervals observed during the most recently completed frame.

The decisive result was:

```text
[FAIL:ERR] ... ERR=0118 RAWB=0272 RAWL=00F0
```

Hexadecimal `0x0272` is 626 bytes, while `0x00F0` is exactly 240 lines. This
proved that VSYNC polarity, HREF polarity, PCLK activity, and vertical scaling
were good. The camera was consistently producing a horizontal active window
14 bytes shorter than required.

## 5. The missing QVGA window registers

The initial table selected QVGA scaling but relied on reset/default horizontal
window values. The measured `626`-byte line showed that assumption was wrong
for this `0x7673` module.

We compared the implementation with the Linux OV7670 driver's QVGA window and
added the six explicit window registers:

| Register | Value | Purpose |
|---|---:|---|
| `HSTART` (`0x17`) | `0x15` | horizontal start high bits |
| `HSTOP` (`0x18`) | `0x03` | horizontal stop high bits |
| `HREF` (`0x32`) | `0x80` | horizontal start/stop low bits |
| `VSTART` (`0x19`) | `0x03` | vertical start high bits |
| `VSTOP` (`0x1A`) | `0x7B` | vertical stop high bits |
| `VREF` (`0x03`) | `0x00` | vertical start/stop low bits |

The write count increased from `WR=003C` to `WR=0042`: one reset write plus 65
configuration writes. The next frame contained the exact expected data:

```text
RAWB=0280 RAWL=00F0 LINE=00F0 PIX=00012C00 OUT=000127A4
```

This was the point at which the physical byte and line dimensions were proven.

## 6. A valid stream still left sticky `ERR=0010`

The first run with the corrected window reported:

```text
[FAIL:ERR] ... F=00000001 LINE=00F0 PIX=00012C00 OUT=000127A4
ERR=0010 RAWB=0280 RAWL=00D5
```

Every completed-frame count was correct, but the sticky frame-height flag had
already observed 213 lines (`0x00D5`). The capture block had left reset in the
middle of a frame and counted the remaining fragment as if it were a complete
frame. Later good frames could not erase a sticky error, so the line remained
red even though the stream had recovered.

The capture block now ignores HREF and data until it has observed the first
VSYNC boundary after reset. This makes the first counted frame complete by
construction. The DVP testbench was extended to send a partial line before
that boundary and verify that it is ignored.

## 7. Final proof

The final hardware-tested bitstream produced:

```text
[PASS:PASS] M3 ID=7673 CFG=P WR=0042 NACK=0000 F=00000002 LINE=00F0 PIX=00012C00 GRAY=B4784EF0 OUT=000127A4 SOB=6A41EC97 ERR=0000 RAWB=0280 RAWL=00F0
```

The same complete counts and CRCs continued through `F=00000132`, decimal
frame 306. There was no failure in the final supplied capture.

## What made the debugging effective

1. We separated camera control (`ID`, `CFG`, `WR`, `NACK`) from camera data
   (`RAWB`, `RAWL`) and pipeline results (`PIX`, `OUT`, CRCs).
2. We decoded error bits instead of treating `ERR` as one generic failure.
3. We added the smallest diagnostics that distinguished polarity, width,
   height, and downstream continuity.
4. We used measured hardware behavior to challenge reset-value assumptions.
5. We reproduced the startup boundary problem in simulation before accepting
   the RTL fix.
6. We required sustained identical results, not one green UART line.

The general rule for Milestone 4 is the same: expose link state, management
register values, packet lengths, packet counts, sequence numbers, and CRC
results separately. A compact but well-chosen measurement is more useful than
a broad `ETH FAIL` flag.
