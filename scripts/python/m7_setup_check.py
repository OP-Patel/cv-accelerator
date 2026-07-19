#!/usr/bin/env python3
"""Read-only M7 dependency, adapter, UDP echo, and FPGA health checks."""

from __future__ import annotations

import argparse
import platform
import socket
import sys


def dependency_versions() -> dict[str, str]:
    versions = {"python": platform.python_version()}
    for module_name in ("numpy", "cv2", "streamlit", "psutil"):
        try:
            module = __import__(module_name)
            versions[module_name] = getattr(module, "__version__", "installed")
        except ImportError:
            versions[module_name] = "MISSING"
    return versions


def local_ipv4_assignments() -> dict[str, list[str]]:
    try:
        import psutil
    except ImportError:
        return {}
    result: dict[str, list[str]] = {}
    for name, addresses in psutil.net_if_addrs().items():
        result[name] = [address.address for address in addresses
                        if address.family == socket.AF_INET]
    return result


def udp_echo(local_ip: str, fpga_ip: str, timeout: float) -> bool:
    payload = b"M7 setup echo"
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as echo_socket:
        echo_socket.bind((local_ip, 0))
        echo_socket.settimeout(timeout)
        echo_socket.sendto(payload, (fpga_ip, 4000))
        reply, _ = echo_socket.recvfrom(2048)
        return reply == payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="skip board/network checks")
    parser.add_argument("--local-ip", default="192.168.10.1")
    parser.add_argument("--fpga-ip", default="192.168.10.2")
    parser.add_argument("--timeout", type=float, default=2.0)
    args = parser.parse_args()

    versions = dependency_versions()
    for name, version in versions.items():
        print(f"{name:10s} {version}")
    missing = [name for name, version in versions.items() if version == "MISSING"]
    if missing:
        print("FIX: py -3 -m pip install -r scripts/python/requirements-m7.txt")
        return 1
    if args.offline:
        print("PASS: dependency-only M7 setup check")
        return 0

    assignments = local_ipv4_assignments()
    matching = [name for name, addresses in assignments.items() if args.local_ip in addresses]
    if not matching:
        print(f"FAIL: {args.local_ip} is not assigned to a local adapter")
        print('FIX (run explicitly in an elevated PowerShell after choosing the adapter):')
        print(f'New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress {args.local_ip} '
              '-PrefixLength 24')
        return 1
    print(f"PASS: {args.local_ip} is assigned to {', '.join(matching)}")

    try:
        if not udp_echo(args.local_ip, args.fpga_ip, args.timeout):
            raise RuntimeError("payload mismatch")
        print("PASS: M4 UDP echo")
        from m7_protocol import BUILD_ID, M7StreamClient, PROFILE_NAMES, STREAM_SOBEL

        with M7StreamClient(local_ip=args.local_ip, fpga_ip=args.fpga_ip,
                            timeout=args.timeout) as client:
            status = client.read_status()
            if status.build_id != BUILD_ID:
                raise RuntimeError(f"unexpected build ID 0x{status.build_id:08x}")
            if not status.link_up or not status.core_locked:
                raise RuntimeError("FPGA link/core is not ready for a session check")
            client.start(STREAM_SOBEL, frame_count=1)
            client.stop()
            print("PASS: M7 control START/STOP")
        print(f"PASS: M7 build=0x{status.build_id:08x} profile={PROFILE_NAMES[status.profile]} "
              f"link={int(status.link_up)} core_lock={int(status.core_locked)}")
        if status.error_flags:
            print(f"FAIL: M7 status reports FPGA error flags 0x{status.error_flags:04x}")
            if status.error_flags & 0x0001:
                print("DETAIL: bit 0 is a camera initialization/SCCB acknowledgement or timeout error")
            print("FIX: verify the OV7670 wiring and power, then press BTN1 and rerun this check")
            return 1
        return 0
    except (OSError, TimeoutError, RuntimeError) as error:
        print(f"FAIL: board health check: {error}")
        print("FIX: program the M7 bitstream, set SW2=1, verify Ethernet 2, then press BTN1")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
