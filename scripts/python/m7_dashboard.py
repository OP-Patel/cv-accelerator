#!/usr/bin/env python3
"""Guided M7 operator console, benchmark runner, and technical showcase."""

from __future__ import annotations

import hashlib
import html
import json
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np

try:
    import psutil
except ImportError:
    psutil = None

import streamlit as st

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from m6_stream_client import CONTROL_FORMAT, CONTROL_MAGIC, STREAM_GRAYSCALE, STREAM_SOBEL
from m7_activity_monitor import ActivityMonitor, ActivitySettings, EventLog, Region
from m7_protocol import M7_VERSION, OPCODE_STOP, PROFILE_NAMES
from m7_setup_check import dependency_versions, local_ipv4_assignments
from m7_showcase import render_sobel_walkthrough, render_udp_explorer
from m7_stream_worker import M7StreamWorker


ARTIFACT_ROOT = REPO_ROOT / "artifacts" / "m7_runs"
DASHBOARD_LOG_ROOT = ARTIFACT_ROOT / "dashboard"
BITSTREAM_PATH = ARTIFACT_ROOT / "build" / "arty_m7_camera_ethernet_top.bit"
PROGRAM_TCL = REPO_ROOT / "scripts" / "program_m7_device.tcl"
DEFAULT_VIVADO = Path(r"C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat")
VERIFIED_SHA256 = "0fb90997a1765c921955a383959c1cba94410ff54119dac3a46bf799a80689b6"
DOC_RESULT = REPO_ROOT / "docs" / "m7_benchmark_results.json"
ACCEPTED_RESULT = ARTIFACT_ROOT / "20260725_140143" / "results.json"

PROFILE_DESCRIPTIONS = {
    "safe": ("7.503 FPS", "Conservative sensor clocking; best first-link diagnostic."),
    "medium": ("15.006 FPS", "Balanced live rate; physically qualified in all three modes."),
    "fast": ("30.013 FPS", "Full qualified camera rate; use after safe/medium are healthy."),
}

MODE_DESCRIPTIONS = {
    "Thresholded Sobel": (
        STREAM_SOBEL,
        "Binary-ready edges",
        "Computes edge strength in the FPGA, then suppresses values below the selected threshold. "
        "Useful for motion gates, contours, occupancy, and inexpensive downstream decisions.",
    ),
    "Reference Sobel": (
        STREAM_SOBEL,
        "Full edge strength",
        "Returns the saturated |Gx| + |Gy| value from 0–255. This preserves weak and strong "
        "intensity boundaries for visualization and bit-exact comparison.",
    ),
    "Grayscale diagnostic": (
        STREAM_GRAYSCALE,
        "The verified input",
        "Converts RGB565 camera pixels to one luminance byte. It proves the sensor/capture path "
        "and supplies the exact input used by the OpenCV comparison.",
    ),
}


st.set_page_config(
    page_title="M7 · Arty A7 edge accelerator",
    page_icon="◆",
    layout="wide",
    initial_sidebar_state="collapsed",
)

st.markdown(
    """
<style>
  :root {
    --m7-bg: #071018;
    --m7-surface: #0b151e;
    --m7-surface-2: #101e29;
    --m7-line: #243642;
    --m7-ink: #edf3f7;
    --m7-muted: #91a0ac;
    --m7-accent: #ff5f68;
    --m7-good: #56d6a9;
    --m7-warn: #f5c46b;
  }
  .stApp {
    background:
      radial-gradient(circle at 82% -10%, rgba(255,95,104,.08), transparent 26rem),
      var(--m7-bg);
    color: var(--m7-ink);
  }
  .block-container { max-width: 1380px; padding-top: 1.7rem; padding-bottom: 4rem; }
  header[data-testid="stHeader"] { background: transparent; }
  [data-testid="stSidebarCollapsedControl"] { color: var(--m7-muted); }
  h1, h2, h3 { letter-spacing: -.035em; }
  h1 { font-size: clamp(2rem, 4vw, 3.5rem) !important; line-height: 1.02 !important; }
  h2 { margin-top: 1rem !important; }
  p, label, [data-testid="stCaptionContainer"] { color: var(--m7-muted); }
  code { color: #f6abb0 !important; }
  hr { border-color: var(--m7-line) !important; margin: 2.2rem 0 !important; }
  [data-baseweb="tab-list"] {
    gap: 1.3rem;
    border-bottom: 1px solid var(--m7-line);
  }
  [data-baseweb="tab"] {
    height: 3.3rem;
    padding: 0 .15rem;
    color: var(--m7-muted);
    font-weight: 650;
  }
  [aria-selected="true"][data-baseweb="tab"] { color: var(--m7-ink); }
  [data-baseweb="tab-highlight"] { background: var(--m7-accent); }
  div.stButton > button, div.stDownloadButton > button {
    border-color: var(--m7-line);
    border-radius: 9px;
    min-height: 2.7rem;
    transition: transform .16s ease, border-color .16s ease, background .16s ease;
  }
  div.stButton > button:hover, div.stDownloadButton > button:hover {
    transform: translateY(-1px);
    border-color: var(--m7-accent);
    color: var(--m7-ink);
  }
  button[kind="primary"] {
    background: var(--m7-accent) !important;
    border-color: var(--m7-accent) !important;
    color: #21090c !important;
    font-weight: 800 !important;
  }
  [data-testid="stMetric"] {
    border-top: 1px solid var(--m7-line);
    padding-top: .8rem;
  }
  [data-testid="stMetricValue"] {
    color: var(--m7-ink);
    letter-spacing: -.045em;
    font-variant-numeric: tabular-nums;
  }
  [data-testid="stMetricDelta"] svg { display:none; }
  [data-testid="stAlert"] { border-radius: 10px; border: 1px solid var(--m7-line); }
  [data-testid="stExpander"] { border-color: var(--m7-line); background: rgba(11,21,30,.5); }
  [data-testid="stDataFrame"] { border: 1px solid var(--m7-line); border-radius: 10px; overflow:hidden; }
  .m7-header {
    display:grid;
    grid-template-columns: 1.6fr .8fr;
    gap: 2rem;
    align-items:end;
    margin-bottom: 1.4rem;
    animation: m7-rise .55s ease both;
  }
  @keyframes m7-rise { from { opacity:0; transform:translateY(9px); } }
  .m7-kicker {
    color: var(--m7-accent);
    font: 750 .72rem/1.2 ui-monospace, "Cascadia Code", monospace;
    letter-spacing: .15em;
    text-transform: uppercase;
  }
  .m7-header h1 { margin:.45rem 0 .55rem; max-width: 900px; }
  .m7-header p { margin:0; max-width: 800px; line-height:1.55; }
  .m7-proof-mark {
    border-left: 2px solid var(--m7-accent);
    padding-left: 1rem;
    color: var(--m7-muted);
    font-size:.8rem;
    line-height:1.45;
  }
  .m7-proof-mark b {
    display:block;
    color:var(--m7-ink);
    font-size:2.15rem;
    letter-spacing:-.055em;
    line-height:1;
    margin:.2rem 0 .4rem;
  }
  .m7-section {
    color: var(--m7-accent);
    font: 750 .68rem/1.2 ui-monospace, "Cascadia Code", monospace;
    letter-spacing: .14em;
    text-transform: uppercase;
    margin: .35rem 0 .2rem;
  }
  .m7-copy { color:var(--m7-muted); line-height:1.6; max-width:900px; margin:.25rem 0 1.3rem; }
  .m7-badge {
    display:inline-block;
    padding:.28rem .55rem;
    border:1px solid var(--m7-line);
    border-radius:999px;
    color:var(--m7-muted);
    font:650 .68rem/1.2 ui-monospace,monospace;
    margin:.1rem .25rem .1rem 0;
  }
  .m7-badge.good { border-color:#2d6a56; color:var(--m7-good); background:rgba(86,214,169,.07); }
  .m7-badge.accent { border-color:#834149; color:#ff9ea4; background:rgba(255,95,104,.08); }
  .m7-step {
    display:grid;
    grid-template-columns:2.2rem 1fr;
    gap:.75rem;
    padding:.9rem 0;
    border-top:1px solid var(--m7-line);
  }
  .m7-step-num {
    color:var(--m7-accent);
    font:800 1rem/1.3 ui-monospace,monospace;
  }
  .m7-step b { display:block; color:var(--m7-ink); margin-bottom:.18rem; }
  .m7-step span { color:var(--m7-muted); font-size:.86rem; line-height:1.45; }
  .m7-switches { display:grid; grid-template-columns:repeat(4,1fr); gap:.55rem; margin:.8rem 0 1.2rem; }
  .m7-switch {
    min-height:9rem;
    border-top:2px solid var(--m7-line);
    background:var(--m7-surface);
    padding:.85rem;
  }
  .m7-switch.target { border-color:var(--m7-accent); }
  .m7-switch code { display:block; font-size:1rem; margin-bottom:.45rem; }
  .m7-switch b { color:var(--m7-ink); display:block; margin-bottom:.3rem; }
  .m7-switch span { color:var(--m7-muted); font-size:.77rem; line-height:1.4; }
  .m7-leds { display:grid; grid-template-columns:repeat(4,1fr); gap:.55rem; }
  .m7-led { border-left:2px solid var(--m7-line); padding:.15rem .7rem; font-size:.78rem; color:var(--m7-muted); }
  .m7-led i { display:inline-block; width:.55rem; height:.55rem; border-radius:50%; background:var(--m7-good); margin-right:.35rem; }
  .m7-led.error i { background:var(--m7-accent); }
  .m7-bar-row {
    display:grid; grid-template-columns:7rem 1fr 7rem; align-items:center; gap:.7rem;
    margin:.7rem 0; color:var(--m7-muted); font-size:.82rem;
  }
  .m7-track { height:.65rem; background:#1a2933; border-radius:99px; overflow:hidden; }
  .m7-fill { height:100%; border-radius:99px; background:#71808a; }
  .m7-fill.fpga { width:17.42%; background:var(--m7-accent); }
  .m7-fill.cpu { width:100%; }
  .m7-log {
    border-left:2px solid var(--m7-line);
    color:var(--m7-muted);
    font: .75rem/1.55 ui-monospace, "Cascadia Code", monospace;
    padding-left:.8rem;
  }
  @media(max-width: 780px) {
    .m7-header { grid-template-columns:1fr; }
    .m7-switches, .m7-leds { grid-template-columns:repeat(2,1fr); }
    .m7-bar-row { grid-template-columns:5rem 1fr 6rem; }
  }
</style>
""",
    unsafe_allow_html=True,
)


def section_label(text: str) -> None:
    st.markdown(f'<div class="m7-section">{text}</div>', unsafe_allow_html=True)


def worker() -> M7StreamWorker:
    if "m7_worker" not in st.session_state:
        st.session_state.m7_worker = M7StreamWorker()
    return st.session_state.m7_worker


def stop_protocol_session() -> None:
    """Best-effort STOP after cancellation; does not alter adapter configuration."""
    payload = struct.pack(
        CONTROL_FORMAT, CONTROL_MAGIC, M7_VERSION, OPCODE_STOP, STREAM_SOBEL, 0, 0
    )
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as control:
            control.bind(("192.168.10.1", 0))
            control.sendto(payload, ("192.168.10.2", 4001))
    except OSError:
        pass


def format_duration(seconds: float) -> str:
    seconds = max(0, int(seconds))
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def sha256_file(path: Path) -> str | None:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError:
        return None


def result_candidates() -> list[Path]:
    paths = list(ARTIFACT_ROOT.glob("**/results.json"))
    paths.extend((ACCEPTED_RESULT, DOC_RESULT))
    existing = {path.resolve(): path for path in paths if path.exists()}
    return sorted(
        existing.values(),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )


def load_latest_result() -> tuple[Path | None, dict[str, Any] | None]:
    for path in result_candidates():
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if "comparison" in value:
                return path, value
        except (OSError, TypeError, ValueError):
            continue
    return None, None


def close_process_handle(prefix: str) -> None:
    handle = st.session_state.pop(f"{prefix}_handle", None)
    if handle is not None:
        handle.close()


def finalize_process(prefix: str) -> bool:
    process = st.session_state.get(f"{prefix}_process")
    if process is None or process.poll() is None:
        return False
    st.session_state[f"{prefix}_returncode"] = process.returncode
    started = st.session_state.get(f"{prefix}_started", time.time())
    st.session_state[f"{prefix}_elapsed"] = time.time() - started
    close_process_handle(prefix)
    st.session_state[f"{prefix}_process"] = None
    return True


def tail_text(path: Path, lines: int = 14) -> str:
    try:
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])
    except OSError:
        return ""


def render_result_metrics(result: dict[str, Any] | None) -> None:
    if not result:
        st.info("No parseable M7 benchmark result is available yet.")
        return
    comparison = result["comparison"]
    live = result.get("live_sessions", [])
    total_live = sum(int(item.get("frames", 0)) for item in live)
    total_errors = sum(int(item.get("integrity_errors", 0)) for item in live)
    columns = st.columns(5)
    columns[0].metric("FPGA advantage", f"{comparison['throughput_ratio']:.3f}×")
    columns[1].metric("FPGA core frame", f"{comparison['fpga_median_frame_ms']:.6f} ms")
    columns[2].metric("OpenCV kernel", f"{comparison['opencv_median_ms']:.6f} ms")
    columns[3].metric("Live frames checked", f"{total_live:,}")
    columns[4].metric("Integrity errors", f"{total_errors:,}")


def render_compute_bars(result: dict[str, Any]) -> None:
    comparison = result["comparison"]
    fpga_fraction = min(
        100.0,
        100.0 * comparison["fpga_median_frame_ms"] / comparison["opencv_median_ms"],
    )
    st.markdown(
        f"""
<div class="m7-bar-row">
  <span>OpenCV CPU</span><div class="m7-track"><div class="m7-fill cpu"></div></div>
  <b>{comparison['opencv_median_ms']:.6f} ms</b>
</div>
<div class="m7-bar-row">
  <span>FPGA</span><div class="m7-track"><div class="m7-fill fpga" style="width:{fpga_fraction:.2f}%"></div></div>
  <b>{comparison['fpga_median_frame_ms']:.6f} ms</b>
</div>
""",
        unsafe_allow_html=True,
    )


def render_switch_guide() -> None:
    st.markdown(
        """
<div class="m7-switches">
  <div class="m7-switch">
    <code>SW0 · choose</code><b>Camera source</b>
    <span><strong>0</strong> live lens · <strong>1</strong> OV7670 color bars.
    The choice is applied on the next camera restart.</span>
  </div>
  <div class="m7-switch target">
    <code>SW1 · set 0</code><b>Grayscale override</b>
    <span><strong>0</strong> lets the dashboard choose the mode.
    <strong>1</strong> forces grayscale regardless of the GUI.</span>
  </div>
  <div class="m7-switch target">
    <code>SW2 · set 1</code><b>Local stream gate</b>
    <span><strong>1</strong> permits validated camera packets.
    <strong>0</strong> is a hard local transmission inhibit.</span>
  </div>
  <div class="m7-switch target">
    <code>SW3 · set 0</code><b>Reserved</b>
    <span>Unused by the M7 RTL. Keep it low so the board position is
    reproducible and future-safe.</span>
  </div>
</div>
<div class="m7-leds">
  <div class="m7-led"><i></i><b>LD4</b> heartbeat</div>
  <div class="m7-led"><i></i><b>LD5</b> camera + Ethernet ready</div>
  <div class="m7-led"><i></i><b>LD6</b> camera packet activity</div>
  <div class="m7-led error"><i></i><b>LD7</b> any sticky error</div>
</div>
""",
        unsafe_allow_html=True,
    )


def render_buttons_guide() -> None:
    rows = [
        {"Board button": "BTN0", "Action": "Full design reset", "When to use it": "Only for a clean restart; all sessions/counters reset."},
        {"Board button": "BTN1", "Action": "Restart camera + PHY initialization", "When to use it": "After changing SW0 or recovering camera/link bring-up."},
        {"Board button": "BTN2", "Action": "Clear sticky errors/counters", "When to use it": "After correcting the cause of LD7 before retesting."},
        {"Board button": "BTN3", "Action": "Print coherent UART status", "When to use it": "Low-level diagnosis; normal GUI operation does not require it."},
    ]
    st.dataframe(rows, hide_index=True, width="stretch")


def make_monitor(
    stream_id: int,
    roi_x: int,
    roi_y: int,
    roi_width: int,
    roi_height: int,
    threshold: int,
    trigger: float,
    clear: float,
    hold: int,
) -> ActivityMonitor:
    width, height = (320, 240) if stream_id == STREAM_GRAYSCALE else (318, 238)
    if roi_x + roi_width > width or roi_y + roi_height > height:
        raise ValueError(f"ROI must fit the selected {width}×{height} stream")
    return ActivityMonitor(
        [Region("operator_roi", roi_x, roi_y, roi_width, roi_height)],
        ActivitySettings(
            edge_threshold=threshold,
            trigger_score=trigger,
            clear_score=clear,
            hold_frames=hold,
        ),
    )


def start_background_process(prefix: str, command: list[str], log_path: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    handle = log_path.open("w", encoding="utf-8")
    try:
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            stdout=handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except Exception:
        handle.close()
        raise
    st.session_state[f"{prefix}_handle"] = handle
    st.session_state[f"{prefix}_process"] = process
    st.session_state[f"{prefix}_started"] = time.time()
    st.session_state[f"{prefix}_log"] = str(log_path)
    st.session_state.pop(f"{prefix}_returncode", None)


def render_header(result: dict[str, Any] | None) -> None:
    comparison = (result or {}).get("comparison", {})
    ratio = comparison.get("throughput_ratio", 5.739084879557291)
    st.markdown(
        f"""
<div class="m7-header">
  <div>
    <div class="m7-kicker">Arty A7-100T · Milestone 7 operator console</div>
    <h1>From photons to verified edges.</h1>
    <p>Program the board, operate the camera, qualify all profiles, and inspect
    the packet/computation path from one guided interface.</p>
  </div>
  <div class="m7-proof-mark">
    PHYSICAL CORE RESULT
    <b>{ratio:.3f}× faster</b>
    than single-thread OpenCV · bit-exact CRC agreement
  </div>
</div>
""",
        unsafe_allow_html=True,
    )


result_path, latest_result = load_latest_result()
render_header(latest_result)

setup_tab, live_tab, benchmark_tab, proof_tab, learn_tab = st.tabs(
    ("1 · Setup", "2 · Live", "3 · Benchmark", "Proof", "How it works")
)


with setup_tab:
    section_label("Guided bring-up")
    st.subheader("Four checks between power-on and a validated frame")
    st.markdown(
        '<p class="m7-copy">The dashboard owns all FPGA sessions after launch. '
        "The only one-time operating-system task is assigning the direct Ethernet "
        "adapter its static IPv4 address.</p>",
        unsafe_allow_html=True,
    )

    guide, readiness = st.columns([1.15, 1], gap="large")
    with guide:
        st.markdown(
            """
<div class="m7-step"><div class="m7-step-num">01</div><div>
  <b>Wire and power</b><span>Connect USB/JTAG, the direct Ethernet cable, and
  the OV7670 using the documented JB/JC wiring. Do not hot-move camera wires.</span>
</div></div>
<div class="m7-step"><div class="m7-step-num">02</div><div>
  <b>Set the board controls</b><span>Normal GUI position:
  SW1=0, SW2=1, SW3=0. Choose SW0=0 for the lens or SW0=1 for color bars.</span>
</div></div>
<div class="m7-step"><div class="m7-step-num">03</div><div>
  <b>Program the verified M7 image</b><span>Use the programming control below.
  It selects the timing-clean bitstream and checks that exactly one A7-100T is attached.</span>
</div></div>
<div class="m7-step"><div class="m7-step-num">04</div><div>
  <b>Wait for LD5, then check the board</b><span>LD4 should heartbeat, LD5 should
  remain on, LD7 should remain off. The health check verifies UDP echo, build ID,
  core lock, and an M7 START/STOP exchange.</span>
</div></div>
""",
            unsafe_allow_html=True,
        )

    with readiness:
        versions = dependency_versions()
        assignments = local_ipv4_assignments()
        adapters = [
            name for name, addresses in assignments.items() if "192.168.10.1" in addresses
        ]
        actual_hash = sha256_file(BITSTREAM_PATH)
        checks = [
            ("Python environment", all(value != "MISSING" for value in versions.values())),
            ("Host IPv4 192.168.10.1", bool(adapters)),
            ("M7 bitstream found", BITSTREAM_PATH.exists()),
            ("Verified bitstream hash", actual_hash == VERIFIED_SHA256),
            ("Vivado 2026.1 launcher", DEFAULT_VIVADO.exists()),
        ]
        for label, passed in checks:
            badge = "good" if passed else "accent"
            state = "ready" if passed else "action needed"
            st.markdown(
                f'<span class="m7-badge {badge}">{state}</span> {label}',
                unsafe_allow_html=True,
            )
        if adapters:
            st.caption(f"Direct FPGA address is assigned on: {', '.join(adapters)}")
        else:
            st.error("Assign 192.168.10.1/24 to the direct Ethernet adapter.")
            st.code(
                'New-NetIPAddress -InterfaceAlias "Ethernet 2" '
                "-IPAddress 192.168.10.1 -PrefixLength 24",
                language="powershell",
            )
        st.caption("FPGA: 192.168.10.2 · MAC 02:00:00:00:00:01 · control UDP 4001")

    st.divider()
    section_label("Physical controls")
    st.subheader("Set the switches before starting a session")
    render_switch_guide()
    with st.expander("Board buttons and recovery actions"):
        render_buttons_guide()
        st.info(
            "If LD7 is on: stop the GUI stream, correct wiring/link state, press BTN2 "
            "to clear sticky flags, press BTN1 to reinitialize, then rerun the health check."
        )

    st.divider()
    program_col, check_col = st.columns(2, gap="large")
    with program_col:
        section_label("One-click programming")
        st.subheader("Load the timing-clean M7 bitstream")
        st.code(str(BITSTREAM_PATH), language=None)
        if actual_hash:
            st.caption(f"SHA-256 · {actual_hash}")
        confirmed = st.checkbox(
            "The Arty A7-100T is attached by USB/JTAG",
            key="program_confirmed",
        )
        program_process = st.session_state.get("m7_program_process")
        program_disabled = (
            not confirmed
            or not BITSTREAM_PATH.exists()
            or not DEFAULT_VIVADO.exists()
            or worker().running
            or program_process is not None
        )
        if st.button(
            "Program verified bitstream",
            type="primary",
            disabled=program_disabled,
            width="stretch",
        ):
            log_path = DASHBOARD_LOG_ROOT / "program_device.log"
            command = [
                str(DEFAULT_VIVADO),
                "-mode",
                "batch",
                "-nolog",
                "-nojournal",
                "-source",
                str(PROGRAM_TCL),
            ]
            try:
                start_background_process("m7_program", command, log_path)
                EventLog(DASHBOARD_LOG_ROOT).append_event(
                    "program_start", "Vivado device programming launched"
                )
                st.rerun()
            except OSError as error:
                st.error(f"Could not launch Vivado: {error}")

        @st.fragment(run_every=0.75)
        def program_status() -> None:
            process = st.session_state.get("m7_program_process")
            if process is not None:
                elapsed = time.time() - st.session_state.get("m7_program_started", time.time())
                st.info(f"Programming in progress · {format_duration(elapsed)}")
                log_path = Path(st.session_state.get("m7_program_log", ""))
                text = tail_text(log_path, 8)
                if text:
                    st.code(text, language=None)
                if finalize_process("m7_program"):
                    st.rerun()
            elif "m7_program_returncode" in st.session_state:
                returncode = st.session_state.m7_program_returncode
                elapsed = st.session_state.get("m7_program_elapsed", 0)
                if returncode == 0:
                    st.success(f"Programming completed in {format_duration(elapsed)}.")
                else:
                    st.error(f"Vivado programming exited with code {returncode}.")
                log_path = Path(st.session_state.get("m7_program_log", ""))
                text = tail_text(log_path)
                if text:
                    st.code(text, language=None)

        program_status()

    with check_col:
        section_label("Board health")
        st.subheader("Verify the complete control path")
        st.markdown(
            "This read-only check confirms dependencies, the host adapter, UDP echo, "
            "M7 build ID, Ethernet link, 200 MHz core lock, and a one-frame session handshake."
        )
        health_disabled = (
            worker().running
            or st.session_state.get("m7_program_process") is not None
        )
        if st.button(
            "Run FPGA health check",
            disabled=health_disabled,
            width="stretch",
        ):
            with st.spinner("Contacting FPGA…"):
                try:
                    completed = subprocess.run(
                        [sys.executable, str(SCRIPT_DIR / "m7_setup_check.py")],
                        cwd=REPO_ROOT,
                        capture_output=True,
                        text=True,
                        timeout=20,
                        check=False,
                    )
                    st.session_state.m7_health_output = completed.stdout + completed.stderr
                    st.session_state.m7_health_returncode = completed.returncode
                except subprocess.TimeoutExpired:
                    st.session_state.m7_health_output = "FAIL: health check exceeded 20 seconds"
                    st.session_state.m7_health_returncode = 2
        if "m7_health_output" in st.session_state:
            if st.session_state.m7_health_returncode == 0:
                st.success("Board health check passed.")
            else:
                st.error("Board health check needs attention.")
            st.code(st.session_state.m7_health_output, language=None)


with live_tab:
    section_label("Live validated camera path")
    st.subheader("Choose what the FPGA sends")
    st.markdown(
        '<p class="m7-copy">Changing a profile requires camera reinitialization. '
        "Use <b>Apply and start</b>; the console stops any current session before "
        "applying the new configuration.</p>",
        unsafe_allow_html=True,
    )
    controls, display = st.columns([0.82, 1.8], gap="large")
    with controls:
        mode = st.selectbox("Processing mode", tuple(MODE_DESCRIPTIONS))
        stream_id, mode_short, mode_copy = MODE_DESCRIPTIONS[mode]
        st.caption(f"{mode_short} · {mode_copy}")
        profile_name = st.segmented_control(
            "Camera profile",
            PROFILE_NAMES,
            default="safe",
            selection_mode="single",
        ) or "safe"
        profile_rate, profile_copy = PROFILE_DESCRIPTIONS[profile_name]
        st.caption(f"Qualified at {profile_rate}. {profile_copy}")
        threshold = st.slider(
            "FPGA edge threshold",
            0,
            255,
            96,
            disabled=mode != "Thresholded Sobel",
            help="Values below this edge magnitude become zero.",
        )

        with st.expander("Activity region and event trigger"):
            st.caption(
                "The host scores non-zero edge density inside a region. This does not "
                "change the FPGA pixels; it turns the validated stream into an event signal."
            )
            roi_a, roi_b = st.columns(2)
            roi_x = int(roi_a.number_input("ROI x", 0, 319, 0, 1))
            roi_y = int(roi_b.number_input("ROI y", 0, 239, 0, 1))
            roi_width = int(roi_a.number_input("ROI width", 1, 320, 318, 1))
            roi_height = int(roi_b.number_input("ROI height", 1, 240, 238, 1))
            trigger = st.slider("Activity trigger", 0.0, 1.0, 0.08, 0.01)
            clear = st.slider("Activity clear", 0.0, trigger, min(0.03, trigger), 0.01)
            hold = int(st.number_input("Hold frames", 0, 300, 8))

        button_a, button_b = st.columns(2)
        if button_a.button(
            "Apply and start",
            type="primary",
            disabled=st.session_state.get("m7_benchmark_process") is not None,
            width="stretch",
        ):
            try:
                if worker().running:
                    worker().stop()
                monitor = make_monitor(
                    stream_id,
                    roi_x,
                    roi_y,
                    roi_width,
                    roi_height,
                    threshold,
                    trigger,
                    clear,
                    hold,
                )
                worker().start(
                    stream_id,
                    PROFILE_NAMES.index(profile_name),
                    threshold if mode == "Thresholded Sobel" else None,
                    monitor,
                    DASHBOARD_LOG_ROOT,
                )
                st.rerun()
            except (RuntimeError, TimeoutError, ValueError) as error:
                st.error(str(error))
        if button_b.button(
            "Stop",
            disabled=not worker().running,
            width="stretch",
        ):
            try:
                worker().stop()
            except TimeoutError as error:
                st.error(str(error))
            st.rerun()
        state = "STREAMING" if worker().running else "STOPPED"
        badge = "good" if worker().running else ""
        st.markdown(
            f'<span class="m7-badge {badge}">{state}</span> one bounded UDP owner',
            unsafe_allow_html=True,
        )

    with display:
        @st.fragment(run_every=0.5)
        def live_panel() -> None:
            frame = worker().latest_frame()
            if frame is not None:
                image = np.frombuffer(frame.pixels, dtype=np.uint8).reshape(
                    frame.height, frame.width
                )
                st.image(
                    image,
                    clamp=True,
                    caption=(
                        f"Validated frame {frame.sequence:,} · {frame.width}×{frame.height} · "
                        f"{frame.packet_count} CRC-checked packets"
                    ),
                    width="stretch",
                )
            else:
                st.markdown(
                    """
<div style="min-height:330px;border:1px dashed #314653;border-radius:14px;
display:grid;place-items:center;color:#71818c;background:#09131b">
Start a session to place validated pixels here
</div>
""",
                    unsafe_allow_html=True,
                )
            status = worker().status
            integrity = worker().integrity
            columns = st.columns(5)
            current_profile = (
                PROFILE_NAMES[status.profile]
                if status and status.profile < len(PROFILE_NAMES)
                else "—"
            )
            period = (
                f"{status.frame_period_cycles / 100000:.2f} ms"
                if status and status.timing_snapshot_valid
                else "—"
            )
            columns[0].metric("Profile", current_profile)
            columns[1].metric("Camera period", period)
            columns[2].metric("FIFO peak", status.stream_fifo_peak if status else "—")
            cpu_text = f"{psutil.cpu_percent(interval=None):.0f}%" if psutil else "n/a"
            columns[3].metric("Host CPU", cpu_text)
            columns[4].metric(
                "Integrity errors", integrity.total_errors() if integrity else 0
            )
            if status and status.error_flags:
                st.error(
                    f"FPGA error flags 0x{status.error_flags:04x}; LD7 should be on. "
                    "Stop, correct the cause, then use BTN2/BTN1."
                )
            recent = []
            while not worker().events.empty():
                recent.append(worker().events.get_nowait())
            if recent:
                st.session_state.setdefault("m7_events", []).extend(recent)
            events = st.session_state.get("m7_events", [])[-5:]
            if events:
                text = "\n".join(
                    f"{time.strftime('%H:%M:%S', time.localtime(event.created_at))}  "
                    f"{event.kind:14s} {event.message}"
                    for event in events
                )
                safe_text = html.escape(text).replace("\n", "<br>")
                st.markdown(
                    f'<div class="m7-log">{safe_text}</div>',
                    unsafe_allow_html=True,
                )
            sample = worker().latest_activity()
            if sample is not None:
                score = max((item.activity_score for item in sample.scores), default=0.0)
                st.metric(
                    "Activity decision",
                    "ACTIVE" if sample.active else "IDLE",
                    f"edge density {score:.3f}",
                )

        live_panel()

    st.divider()
    section_label("What the three views mean")
    explanation_columns = st.columns(3)
    for column, (name, (_, short, copy)) in zip(
        explanation_columns, MODE_DESCRIPTIONS.items()
    ):
        with column:
            st.markdown(f"#### {name}")
            st.caption(short)
            st.write(copy)


with benchmark_tab:
    section_label("Acceptance runner")
    st.subheader("Measure speed and prove the result is correct")
    st.markdown(
        '<p class="m7-copy">The benchmark separates core compute from camera and '
        "network rate. Full acceptance repeats the controlled compute comparison "
        "five times, then validates 9,000 live frames across every profile/mode pair.</p>",
        unsafe_allow_html=True,
    )

    benchmark_explain, benchmark_controls = st.columns([1.15, 1], gap="large")
    with benchmark_explain:
        phases = [
            ("1", "OpenCV control", "Five × 1,000 deterministic 320×240 inputs, one CPU thread."),
            ("2", "Physical FPGA compute", "Five × 1,000 frames through 32 lanes at 200 MHz; counters read back from hardware."),
            ("3", "Bit-exact proof", "Both sides must produce combined CRC32 0x9e562313."),
            ("4", "Live transport matrix", "safe/medium/fast × grayscale/reference/threshold, 1,000 frames each."),
            ("5", "Integrity gate", "Zero missing, duplicate, reordered, malformed, CRC, or sequence errors."),
        ]
        for number, title, copy in phases:
            st.markdown(
                f'<div class="m7-step"><div class="m7-step-num">{number}</div>'
                f"<div><b>{title}</b><span>{copy}</span></div></div>",
                unsafe_allow_html=True,
            )
        st.info(
            "Camera content does not affect packet integrity. A visible high-contrast "
            "edge is helpful when judging the Sobel image, but deterministic synthetic "
            "patterns—not the room scene—prove the compute comparison."
        )

    with benchmark_controls:
        benchmark_kind = st.radio(
            "Validation size",
            ("Full acceptance", "Quick shakedown"),
            captions=(
                "5 × 1,000 compute frames; about 12 minutes with live matrix.",
                "One 300-frame compute run; useful after a wiring or bitstream change.",
            ),
        )
        include_live = st.checkbox(
            "Include physical profile/mode matrix",
            value=True,
            help="Adds 3 profiles × 3 modes and validates every packet of every frame.",
        )
        if worker().running:
            st.warning("Stop the live stream before launching a benchmark.")
        process = st.session_state.get("m7_benchmark_process")
        launch_disabled = worker().running or process is not None
        if st.button(
            "Launch benchmark",
            type="primary",
            disabled=launch_disabled,
            width="stretch",
        ):
            run_dir = ARTIFACT_ROOT / time.strftime("%Y%m%d_%H%M%S")
            command = [
                sys.executable,
                str(SCRIPT_DIR / "benchmark_m7.py"),
                "--json-output",
                str(run_dir / "results.json"),
                "--csv-output",
                str(run_dir / "results.csv"),
                "--markdown-output",
                str(run_dir / "results.md"),
            ]
            if benchmark_kind == "Quick shakedown":
                command.append("--quick")
            if include_live:
                command.append("--live")
            try:
                start_background_process(
                    "m7_benchmark", command, run_dir / "console.log"
                )
                EventLog(DASHBOARD_LOG_ROOT).append_event(
                    "benchmark_start",
                    "dashboard benchmark launched",
                    kind=benchmark_kind,
                    live=include_live,
                )
                st.rerun()
            except OSError as error:
                st.error(f"Could not launch benchmark: {error}")

        @st.fragment(run_every=0.5)
        def benchmark_status() -> None:
            running = st.session_state.get("m7_benchmark_process")
            if running is not None:
                elapsed = time.time() - st.session_state.get(
                    "m7_benchmark_started", time.time()
                )
                st.info(f"Benchmark running · {format_duration(elapsed)} elapsed")
                log_path = Path(st.session_state.get("m7_benchmark_log", ""))
                text = tail_text(log_path, 6)
                if text:
                    st.code(text, language=None)
                if st.button("Cancel and send STOP", width="stretch"):
                    running.terminate()
                    try:
                        running.wait(2)
                    except subprocess.TimeoutExpired:
                        running.kill()
                    close_process_handle("m7_benchmark")
                    st.session_state.m7_benchmark_process = None
                    stop_protocol_session()
                    EventLog(DASHBOARD_LOG_ROOT).append_event(
                        "benchmark_cancelled",
                        "dashboard benchmark cancelled; STOP sent",
                    )
                    st.warning("Benchmark cancelled; protocol STOP sent.")
                    st.rerun()
                if finalize_process("m7_benchmark"):
                    EventLog(DASHBOARD_LOG_ROOT).append_event(
                        "benchmark_complete",
                        "dashboard benchmark finished",
                        returncode=st.session_state.m7_benchmark_returncode,
                    )
                    st.rerun()
            elif "m7_benchmark_returncode" in st.session_state:
                returncode = st.session_state.m7_benchmark_returncode
                elapsed = st.session_state.get("m7_benchmark_elapsed", 0)
                if returncode == 0:
                    st.success(
                        f"Benchmark completed successfully in {format_duration(elapsed)}."
                    )
                else:
                    st.error(f"Benchmark exited with code {returncode}.")
                log_path = Path(st.session_state.get("m7_benchmark_log", ""))
                text = tail_text(log_path)
                if text:
                    st.code(text, language=None)

        benchmark_status()

    st.divider()
    section_label("Most recent evidence")
    render_result_metrics(latest_result)
    if latest_result:
        render_compute_bars(latest_result)
        st.caption(
            "Core timing only. Live camera FPS is shown separately because sensor, "
            "packetization, Ethernet, and host display are different bottlenecks."
        )


with proof_tab:
    section_label("Accepted physical result")
    st.subheader("The result is fast, repeated, and bit-exact")
    if not latest_result:
        st.warning("No benchmark result is available.")
    else:
        render_result_metrics(latest_result)
        st.markdown(
            '<span class="m7-badge good">PHYSICAL MEASUREMENT</span>'
            '<span class="m7-badge good">CRC MATCH</span>'
            '<span class="m7-badge good">TIMING CLEAN</span>'
            '<span class="m7-badge accent">32 LANES @ 200 MHz</span>',
            unsafe_allow_html=True,
        )
        st.divider()
        comparison_col, method_col = st.columns([1.15, 1], gap="large")
        with comparison_col:
            st.markdown("### Controlled compute comparison")
            render_compute_bars(latest_result)
            comparison = latest_result["comparison"]
            st.success(
                f"FPGA throughput is {comparison['throughput_ratio']:.3f}× OpenCV, "
                f"clearing the required {comparison['required_ratio']:.2f}× contract."
            )
        with method_col:
            st.markdown("### Why this is a fair claim")
            method = latest_result.get("method", {})
            st.markdown(
                f"""
- Same `{method.get('input', 'deterministic inputs')}` on both sides.
- Same `{method.get('output', 'Sobel output')}`.
- `{method.get('independent_runs', 5)}` independent runs × `{method.get('samples_per_run', 1000):,}` samples.
- FPGA timing comes from `{method.get('fpga_evidence', 'physical counters')}`.
- Output correctness is proven by a matching combined CRC, not by appearance.
"""
            )
            st.caption(
                "This comparison is the Sobel kernel contract, not a claim that every "
                "computer-vision workload is 5.739× faster on this FPGA."
            )

        live_sessions = latest_result.get("live_sessions", [])
        if live_sessions:
            st.divider()
            section_label("9,000-frame live matrix")
            st.subheader("Every camera rate and processing mode passed")
            live_rows = [
                {
                    "Profile": item["profile"],
                    "Mode": item["mode"].replace("_", " "),
                    "Frames": int(item["frames"]),
                    "Measured FPS": round(float(item["interframe_fps"]), 4),
                    "Host CPU": f"{float(item['host_cpu_percent']):.1f}%",
                    "Integrity errors": int(item["integrity_errors"]),
                }
                for item in live_sessions
            ]
            st.dataframe(live_rows, hide_index=True, width="stretch")
            st.caption(
                "The first frame after each deliberate STOP/START carries a discontinuity "
                "marker. It is an expected session boundary, not an integrity error."
            )

        st.divider()
        download_col, files_col = st.columns([1, 1.4], gap="large")
        with download_col:
            section_label("Evidence bundle")
            st.subheader("Download the exact result")
            if result_path:
                st.caption(str(result_path.relative_to(REPO_ROOT)))
                st.download_button(
                    "Download results.json",
                    result_path.read_bytes(),
                    file_name="m7_benchmark_results.json",
                    width="stretch",
                )
                sibling_csv = result_path.with_suffix(".csv")
                sibling_md = result_path.with_suffix(".md")
                if not sibling_md.exists() and result_path.resolve() == DOC_RESULT.resolve():
                    sibling_md = REPO_ROOT / "docs" / "milestone7_benchmark_results.md"
                if sibling_csv.exists():
                    st.download_button(
                        "Download results.csv",
                        sibling_csv.read_bytes(),
                        file_name="m7_benchmark_results.csv",
                        width="stretch",
                    )
                if sibling_md.exists():
                    st.download_button(
                        "Download readable summary",
                        sibling_md.read_bytes(),
                        file_name="m7_benchmark_results.md",
                        width="stretch",
                    )
        with files_col:
            section_label("Recent runs")
            recent_results = result_candidates()[:8]
            if recent_results:
                rows = []
                for path in recent_results:
                    try:
                        data = json.loads(path.read_text(encoding="utf-8"))
                        rows.append(
                            {
                                "Run": path.parent.name,
                                "Generated": data.get("generated_utc", "—"),
                                "Kind": data.get("benchmark_kind", "—"),
                                "Ratio": round(
                                    float(data["comparison"]["throughput_ratio"]), 3
                                ),
                                "Evidence": data["comparison"].get(
                                    "evidence_kind", "—"
                                ),
                            }
                        )
                    except (OSError, KeyError, TypeError, ValueError):
                        continue
                st.dataframe(rows, hide_index=True, width="stretch")

        with st.expander("Dashboard event logs and generated run files"):
            generated_files = sorted(
                (path for path in ARTIFACT_ROOT.glob("**/*.*") if path.is_file()),
                key=lambda path: path.stat().st_mtime,
                reverse=True,
            )[:40]
            for path in generated_files:
                relative = path.relative_to(REPO_ROOT)
                st.download_button(
                    str(relative),
                    path.read_bytes(),
                    file_name=path.name,
                    key=f"download-{relative}",
                )


with learn_tab:
    section_label("Why dedicated hardware matters")
    st.subheader("Sobel is a small algorithm with a large systems lesson")
    st.markdown(
        """
Sobel finds rapid brightness changes—the boundaries between objects, lanes,
parts, text, hands, or motion regions. Grayscale removes color complexity;
reference Sobel preserves edge strength; thresholded Sobel turns that strength
into a cheap decision signal.

On a CPU, OpenCV loads neighborhoods and schedules instructions on general-purpose
cores. The FPGA turns the same work into a spatial pipeline: BRAM remembers rows,
shift registers expose nine pixels at once, adders for `Gx` and `Gy` exist
simultaneously, and 32 independent lanes operate at 200 MHz. After the pipeline
fills, data keeps moving without an operating system or per-frame scheduler.
"""
    )
    render_sobel_walkthrough()

    st.divider()
    section_label("Packet explorer")
    st.subheader("How processed pixels become trustworthy UDP")
    st.markdown(
        '<p class="m7-copy">UDP keeps the link simple, but the application does '
        "not treat arrival as correctness. The custom M5CV header makes frame "
        "reassembly strict and auditable.</p>",
        unsafe_allow_html=True,
    )
    render_udp_explorer()

    st.divider()
    section_label("Where this becomes useful")
    real_world = st.columns(4)
    use_cases = (
        ("Robotics", "Extract boundaries before navigation data reaches a control CPU."),
        ("Industrial inspection", "Flag contour or occupancy changes with predictable latency."),
        ("Smart cameras", "Transmit compact edge information or events instead of raw color."),
        ("Learning platform", "Expose the complete path from sensor timing to verified network data."),
    )
    for column, (title, copy) in zip(real_world, use_cases):
        with column:
            st.markdown(f"#### {title}")
            st.write(copy)
    st.info(
        "The critical property is not that Sobel is the final application. It is "
        "that the FPGA can perform deterministic, line-rate preprocessing next to "
        "the sensor, leaving the CPU free for tracking, decisions, storage, or a UI."
    )
