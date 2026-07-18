# Milestone 4 Ethernet hardware validation

## Current status

The RTL, constraints, simulations, build targets, and host utility are
implemented. Physical Arty A7-100T Ethernet validation has **not yet been
performed in this checkout**. Do not mark Milestone 4 complete until the
evidence checklist below is archived.

## Host and cabling

Use the onboard RJ-45 connector. The PHY is 10/100 only; connect it to a
10/100-capable host port or switch. Configure the selected host adapter as
`192.168.10.1/24` with no gateway for the isolated test. Disable other routes
that claim `192.168.10.0/24`.

Scapy raw modes need Npcap on Windows and an elevated terminal:

```text
python -m pip install scapy
python scripts/python/ethernet_test.py interfaces
```

## Procedure

1. Run the Milestone 4 simulations, synthesis check, and bitstream build.
2. Open the dedicated Milestone 4 project from PowerShell:

   ```powershell
   & "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
     "C:\Users\Om Patel\Desktop\arty-conv-accelerator\vivado_project_m4\arty_conv_m4.xpr"
   ```

   The older `vivado_project\arty_conv.xpr` path is not present. Program
   `vivado_project_m4/arty_conv_m4.runs/impl_1/arty_m4_ethernet_top.bit`.
3. Capture UART at 115200 8N1. With no cable, confirm the PHY identity and
   `LINK=0`. Connect the cable and wait for `LINK=1`.
4. Confirm `SPD=100` on a 100 Mb/s partner. With a deliberate 10 Mb/s partner,
   confirm `SPD=010`. Confirm duplex agrees with the partner.
5. Start raw capture, then press `BTN3`:

   ```text
   python scripts/python/ethernet_test.py raw-listen --interface "Ethernet 2" --count 1
   ```

6. Send 100 raw frames into the FPGA and confirm UART RX increases with zero
   `BAD` and `DROP`:

   ```text
   python scripts/python/ethernet_test.py raw-send --interface "Ethernet 2" --count 100
   ```

7. Clear the host ARP cache, start UDP traffic, and confirm Wireshark shows an
   ARP request and FPGA reply.
8. Run a sustained exact UDP echo test:

   ```text
   python scripts/python/ethernet_test.py udp --count 10000 --interval 0.001
   ```

9. Repeat at negotiated 10 Mb/s if a 10 Mb/s link partner is available.
10. Press `BTN3` for a final UART snapshot and save all evidence.

## Required evidence

- [ ] simulation PASS transcript
- [ ] synthesis and implementation complete
- [ ] nonnegative implemented setup/hold timing
- [ ] reviewed CDC and DRC reports
- [ ] final bitstream SHA-256
- [ ] UART with `PHY=2000:5C9x`, cable-down, and cable-up states
- [ ] exact raw transmit capture
- [ ] 100-frame raw receive with zero protocol/FCS/sequence errors
- [ ] ARP request/reply packet capture
- [ ] 10,000-packet UDP echo PASS summary
- [ ] final UART with `BAD=0`, `DROP=0`, and `ERR=0`
- [ ] negotiated 10 Mb/s result, or a note that no 10 Mb/s partner was available

## Results

Pending physical hardware execution.
