# Milestone 4 Ethernet debugging postmortem

## Outcome

Milestone 4 passed physical testing on July 17, 2026. The final system
negotiated 100 Mb/s full duplex, passed raw Ethernet in both directions,
answered ARP, echoed 10,000 UDP payloads, and ended with `BAD=0`, `DROP=0`, and
`ERR=0`.

The RTL did not require a hardware fix during this bench session. The failures
were host setup, command interpretation, and observability issues. Recording
them matters because each one initially looked like an FPGA receive or UDP
failure.

## 1. Literal interface placeholder

The first raw listener command used:

```text
--interface "INTERFACE"
```

Scapy therefore searched for an adapter literally named `INTERFACE` and
raised:

```text
ValueError: Interface 'INTERFACE' not found !
```

The actual wired adapter was:

```text
Ethernet 2
ASIX AX88179 USB 3.0 to Gigabit Ethernet Adapter
```

Working form:

```powershell
python scripts/python/ethernet_test.py raw-listen --interface "Ethernet 2" --count 1
```

The utility's `interfaces` subcommand also has a compatibility problem with
the installed Scapy/libpcap provider: `get_if_list()` returns Npcap network
names, then `dev_from_name()` tries to treat them as friendly names. If that
helper fails, use Scapy's `conf.ifaces.show()` or Wireshark's capture-interface
list to identify the friendly adapter name.

## 2. Host transmit PASS did not mean FPGA receive PASS

`raw-send` printed:

```text
PASS raw-send frames=100 first=1 last=100
```

That line means Scapy handed the frames to the host interface. It does not
prove the FPGA accepted them. The authoritative receive evidence is a later
UART snapshot showing an RX increase with zero `BAD`, `DROP`, and `ERR`.

## 3. UART appeared not to update

The UART reporter is event driven. Incoming frames and continuous raw
transmissions update counters but do not automatically request a line. Reports
are requested by PHY/link events and button actions.

`SW0` was initially high. The TX count advanced from `0x34D` to `0x35F` in
three seconds, proving continuous raw mode was running. That mode also made a
raw listener pass without a new manual button event, which obscured the test
sequence.

The repeatable fix was:

1. set `SW0=0`;
2. wait for `LINK=1`;
3. press `BTN2` to clear counters;
4. send one raw sequence;
5. press `BTN3` for a fresh UART snapshot.

Because `BTN3` requests a report at the same time that it requests one FPGA
transmission, the printed TX count can precede completion of that new frame by
one. The earlier host-side raw-listen PASS remains the direct TX proof.

## 4. RX exceeded the requested raw count

After sending 100 raw frames, UART reported:

```text
RX=00000073
```

`0x73` is 115 decimal. This was not duplication by the FPGA. The RX counter
counts every valid Ethernet frame, while Windows emits multicast, discovery,
and broadcast traffic on the interface. The correct acceptance rule is an
increase of at least the requested raw count with zero bad/drop/error fields.

## 5. UDP test appeared to hang

The host adapter initially had the automatic private address:

```text
169.254.108.10
```

The FPGA uses fixed address `192.168.10.2`, so the host was not on the same
subnet. The UDP utility sends one packet, waits for its reply, and prints only
one summary after the complete run. With the default one-second timeout,
10,000 missing replies can take almost 2 hours 47 minutes.

The fix was to stop the command, configure `Ethernet 2` as
`192.168.10.1/24` with no gateway or DNS, and prove one packet before running
10,000:

```powershell
arp -d 192.168.10.2
python scripts/python/ethernet_test.py udp --count 1 --timeout 2
```

## 6. Wireshark filter hid ARP

The initial display filter was:

```text
udp
```

That filter can show UDP traffic but necessarily hides the ARP exchange. The
useful acceptance filter is:

```text
arp || udp.port == 4000
```

It exposed the complete path: host ARP request, FPGA ARP reply, UDP request,
and exact UDP echo response.

## 7. Link state changed during early observation

UART first showed `LINK=0 DUP=H`, then changed to `LINK=1 DUP=F` after
auto-negotiation. Traffic testing should begin only after the stable link-up
line. A raw command issued while negotiation is incomplete can fail without
implicating the MAC datapath.

## Lessons carried into Milestone 5

- Make host prerequisites executable and visible before a long test.
- Add periodic progress for long host runs rather than printing only at exit.
- Separate counters for the target protocol from all valid Ethernet traffic.
- Add an explicit UART snapshot control that does not also transmit a frame.
- Learn the streaming destination from a host control packet; do not rely on a
  hard-coded host MAC address.
- Use coherent request/acknowledge snapshots for multi-clock status.
- Preserve M3 and M4 standalone tops so integration failures can be bisected.
