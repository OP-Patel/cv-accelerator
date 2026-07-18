# Milestone 5 camera-over-Ethernet contract

## Fixed network identity

```text
FPGA MAC:        02:00:00:00:00:01
FPGA IPv4:       192.168.10.2
Host IPv4:       192.168.10.1/24
UDP echo port:   4000
Control port:    4001
```

The FPGA learns the host MAC, IPv4 address, and UDP source port from a valid
control request. A reset, PHY restart, link loss, or STOP command invalidates
the active streaming session.

## Control payload

Every control request and acknowledgement is exactly 12 bytes. Multi-byte
values are big-endian.

| Byte | Field |
|---:|---|
| 0..3 | ASCII `M5CT` |
| 4 | protocol version, `1` |
| 5 | opcode: `1` START, `2` STOP, `3` PING |
| 6 | stream: `0` Sobel, `1` grayscale |
| 7 | flags, currently zero |
| 8..11 | requested frame count; zero means continuous |

An ACK repeats the accepted fields and sets bit 7 of the opcode. Invalid
lengths, versions, opcodes, stream IDs, flags, and destinations are rejected
and counted.

## Camera datagram payload

Each camera UDP payload begins with this 32-byte header followed by at most
1,024 raster-ordered 8-bit pixels. No IPv4 fragmentation is used.

| Byte | Width | Field |
|---:|---:|---|
| 0 | 4 | ASCII `M5CV` |
| 4 | 1 | protocol version, `1` |
| 5 | 1 | stream ID |
| 6 | 1 | bit 0 FIRST, bit 1 LAST, bit 2 DISCONTINUITY |
| 7 | 1 | header size, `32` |
| 8 | 4 | frame sequence |
| 12 | 2 | packet index |
| 14 | 2 | packet count |
| 16 | 4 | pixel offset |
| 20 | 2 | image payload length |
| 22 | 2 | output width |
| 24 | 2 | output height |
| 26 | 2 | reserved, zero |
| 28 | 4 | CRC-32 of image bytes in this datagram |

Sobel frames are 318x238: 75,684 bytes in 74 packets, with a 932-byte tail.
Grayscale frames are 320x240: 76,800 bytes in 75 full 1,024-byte packets. A
packet never crosses a frame boundary.

## Overflow and arbitration

The camera has no backpressure. On stream-FIFO overflow, the FPGA marks an
error, discards the remainder of the affected frame, resumes only at a clean
frame start, and marks the recovered frame DISCONTINUITY.

Ethernet transmit ownership is non-preemptive. Priority is ARP, control ACK,
M4 UDP echo, camera data, then the reserved test source. Once granted, a source
owns the transmitter through the end of its Ethernet frame.

## Board controls

- `BTN0`: integrated reset
- `BTN1`: restart camera initialization and PHY discovery
- `BTN2`: clear sticky errors and counters
- `BTN3`: request a coherent UART status snapshot
- `SW0`: OV7670 color bars on the next initialization
- `SW1`: force grayscale instead of Sobel
- `SW2`: local streaming enable; a valid host session is still required
- `LD4`: heartbeat
- `LD5`: camera configured, identified, and Ethernet linked
- `LD6`: camera packet activity
- `LD7`: any combined sticky error
