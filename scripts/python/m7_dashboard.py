#!/usr/bin/env python3
"""Streamlit control surface for M7 setup, streaming, activity, and results."""

from __future__ import annotations

import socket
import struct
import subprocess
import sys
import time
import json
from pathlib import Path

import numpy as np
try:
    import psutil
except ImportError:
    psutil = None
import streamlit as st

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from m6_stream_client import CONTROL_FORMAT, CONTROL_MAGIC, STREAM_GRAYSCALE, STREAM_SOBEL
from m7_activity_monitor import ActivityMonitor, ActivitySettings, EventLog, Region
from m7_protocol import M7_VERSION, OPCODE_STOP, PROFILE_NAMES
from m7_setup_check import dependency_versions, local_ipv4_assignments
from m7_stream_worker import M7StreamWorker

st.set_page_config(page_title="Arty A7 M7 edge monitor", layout="wide")
st.markdown("""
<style>
  .block-container { padding-top: 2rem; padding-bottom: 3rem; }
  [data-testid="stMetricValue"] { letter-spacing: -0.03em; }
  .m7-kicker { color: #f0a45b; font-size: .78rem; letter-spacing: .16em;
               text-transform: uppercase; font-weight: 700; }
</style>
<div class="m7-kicker">M7 / EDGE PROCESSING CONSOLE</div>
""", unsafe_allow_html=True)
st.title("Operate the camera path. Validate the edge path.")
st.caption("One bounded UDP worker owns the session; every frame and counter shown here is validated before display.")


def worker() -> M7StreamWorker:
    if "m7_worker" not in st.session_state:
        st.session_state.m7_worker = M7StreamWorker()
    return st.session_state.m7_worker


def stop_benchmark_session() -> None:
    """Best-effort protocol STOP after cancellation; never changes adapter state."""
    payload = struct.pack(CONTROL_FORMAT, CONTROL_MAGIC, M7_VERSION,
                          OPCODE_STOP, STREAM_SOBEL, 0, 0)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as control:
            control.bind(("192.168.10.1", 0))
            control.sendto(payload, ("192.168.10.2", 4001))
    except OSError:
        pass


setup_tab, live_tab, benchmark_tab, results_tab = st.tabs(
    ("Setup", "Live stream", "Benchmark", "Results and logs")
)

with setup_tab:
    versions = dependency_versions()
    st.subheader("Read-only setup checks")
    st.table([{"component": key, "version": value} for key, value in versions.items()])
    assignments = local_ipv4_assignments()
    adapters = [name for name, addresses in assignments.items() if "192.168.10.1" in addresses]
    if adapters:
        st.success(f"192.168.10.1 is assigned to {', '.join(adapters)}")
    else:
        st.error("192.168.10.1 is not assigned locally")
        st.code('New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 192.168.10.1 -PrefixLength 24')
    if st.button("Run FPGA health check"):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("m7_setup_check.py"))],
            capture_output=True, text=True, timeout=15, check=False,
        )
        st.code(result.stdout + result.stderr)

with live_tab:
    left, right = st.columns([1, 2])
    with left:
        mode = st.selectbox("FPGA stream", ("Thresholded Sobel", "Reference Sobel", "Grayscale diagnostic"))
        profile_name = st.selectbox("Camera profile", PROFILE_NAMES)
        threshold = st.slider("FPGA threshold", 0, 255, 96,
                              disabled=mode != "Thresholded Sobel")
        st.caption("Profile changes stop the current session and restart camera initialization.")
        st.markdown("**Activity region**")
        roi_x = st.number_input("ROI x", min_value=0, max_value=319, value=0, step=1)
        roi_y = st.number_input("ROI y", min_value=0, max_value=239, value=0, step=1)
        roi_width = st.number_input("ROI width", min_value=1, max_value=320, value=318, step=1)
        roi_height = st.number_input("ROI height", min_value=1, max_value=240, value=238, step=1)
        trigger = st.slider("Activity trigger", 0.0, 1.0, 0.08, 0.01)
        clear = st.slider("Activity clear", 0.0, trigger, min(0.03, trigger), 0.01)
        hold = st.number_input("Hold frames", 0, 300, 8)
        if st.button("Start", disabled=worker().running):
            stream_id = STREAM_GRAYSCALE if mode == "Grayscale diagnostic" else STREAM_SOBEL
            width, height = ((320, 240) if stream_id == STREAM_GRAYSCALE else (318, 238))
            if roi_x + roi_width > width or roi_y + roi_height > height:
                st.error(f"ROI must fit the selected {width}x{height} stream")
                st.stop()
            monitor = ActivityMonitor(
                [Region("operator_roi", int(roi_x), int(roi_y),
                         int(roi_width), int(roi_height))],
                ActivitySettings(edge_threshold=threshold, trigger_score=trigger,
                                 clear_score=clear, hold_frames=int(hold)),
            )
            worker().start(stream_id, PROFILE_NAMES.index(profile_name),
                           threshold if mode == "Thresholded Sobel" else None, monitor)
            st.rerun()
        if st.button("Stop", disabled=not worker().running):
            try:
                worker().stop()
            except TimeoutError as error:
                st.error(str(error))
            st.rerun()
        st.metric("Worker", "running" if worker().running else "stopped")

    with right:
        @st.fragment(run_every=0.5)
        def live_panel():
            frame = worker().latest_frame()
            if frame is not None:
                image = np.frombuffer(frame.pixels, dtype=np.uint8).reshape(frame.height, frame.width)
                st.image(image, clamp=True, caption=f"Validated frame {frame.sequence}", width="stretch")
            status = worker().status
            integrity = worker().integrity
            columns = st.columns(5)
            profile = PROFILE_NAMES[status.profile] if status and status.profile < len(PROFILE_NAMES) else "-"
            columns[0].metric("Profile", profile)
            period = (f"{status.frame_period_cycles/100000:.2f} ms"
                      if status and status.timing_snapshot_valid else "-")
            columns[1].metric("Camera period", period)
            columns[2].metric("FIFO peak", status.stream_fifo_peak if status else "-")
            cpu_text = f"{psutil.cpu_percent(interval=None):.0f}%" if psutil else "n/a"
            columns[3].metric("Host CPU", cpu_text)
            columns[4].metric("Integrity errors", integrity.total_errors() if integrity else 0)
            if status and status.error_flags:
                st.error(f"FPGA error flags: 0x{status.error_flags:04x}")
            recent = []
            while not worker().events.empty():
                recent.append(worker().events.get_nowait())
            if recent:
                st.session_state.setdefault("m7_events", []).extend(recent)
            for event in st.session_state.get("m7_events", [])[-5:]:
                (st.error if event.kind == "error" else st.info)(f"{event.kind}: {event.message}")
            sample = worker().latest_activity()
            if sample is not None:
                score = max((item.activity_score for item in sample.scores), default=0.0)
                st.metric("Activity", "ACTIVE" if sample.active else "IDLE", f"score {score:.3f}")
        live_panel()

with benchmark_tab:
    st.warning("Benchmarks require the attached board. Stop live streaming before launch.")
    kind = st.radio("Validation size", ("Quick (300)", "Full acceptance (5 x 1,000)"), horizontal=True)
    include_live = st.checkbox("Include physical profile/mode matrix", value=False)
    process = st.session_state.get("m7_benchmark_process")
    if process is not None and process.poll() is not None:
        st.session_state.m7_benchmark_returncode = process.returncode
        EventLog(Path("artifacts/m7_runs/dashboard")).append_event(
            "benchmark_complete", "dashboard benchmark finished",
            returncode=process.returncode,
        )
        handle = st.session_state.pop("m7_benchmark_handle", None)
        if handle:
            handle.close()
        st.session_state.m7_benchmark_process = None
        process = None
    if st.button("Launch benchmark", disabled=worker().running or process is not None):
        run_dir = Path("artifacts/m7_runs") / time.strftime("%Y%m%d_%H%M%S")
        run_dir.mkdir(parents=True, exist_ok=True)
        command = [sys.executable, str(Path(__file__).with_name("benchmark_m7.py")),
                   "--json-output", str(run_dir / "results.json"),
                   "--csv-output", str(run_dir / "results.csv"),
                   "--markdown-output", str(run_dir / "results.md")]
        if kind.startswith("Quick"):
            command.append("--quick")
        if include_live:
            command.append("--live")
        handle = (run_dir / "console.log").open("w", encoding="utf-8")
        st.session_state.m7_benchmark_handle = handle
        st.session_state.m7_benchmark_started = time.time()
        st.session_state.m7_benchmark_process = subprocess.Popen(
            command, stdout=handle, stderr=subprocess.STDOUT, text=True
        )
        st.rerun()
    process = st.session_state.get("m7_benchmark_process")
    if process is not None:
        st.info(f"Benchmark running for {time.time()-st.session_state.m7_benchmark_started:.1f} s")
        if st.button("Cancel / STOP"):
            process.terminate()
            try:
                process.wait(2)
            except subprocess.TimeoutExpired:
                process.kill()
            stop_benchmark_session()
            st.session_state.m7_benchmark_process = None
            EventLog(Path("artifacts/m7_runs/dashboard")).append_event(
                "benchmark_cancelled", "dashboard benchmark cancelled",
            )
            st.warning("Benchmark cancelled; protocol STOP sent.")

with results_tab:
    st.subheader("Generated runs")
    files = sorted(Path("artifacts/m7_runs").glob("**/*.*"), reverse=True)[:50]
    for path in files:
        if path.is_file():
            st.download_button(str(path), path.read_bytes(), file_name=path.name,
                               key=str(path))
    result_candidates = sorted(
        list(Path("artifacts/m7_runs").glob("**/results.json")) +
        [Path("docs/m7_benchmark_results.json")],
        key=lambda path: path.stat().st_mtime if path.exists() else 0,
        reverse=True,
    )
    for result_path in result_candidates:
        if not result_path.exists():
            continue
        try:
            result = json.loads(result_path.read_text(encoding="utf-8"))
            comparison = result["comparison"]
            st.subheader(f"Latest benchmark: {result_path.parent.name}")
            st.metric("FPGA / OpenCV throughput", f"{comparison['throughput_ratio']:.3f}x")
            st.bar_chart({
                "OpenCV kernel ms": [run.get("median_ms", 0.0) for run in result["opencv_runs"]],
                "FPGA frame ms": [run.get("sustained_frame_ms", 0.0) for run in result["fpga_compute_runs"]],
            })
        except (OSError, KeyError, TypeError, ValueError):
            st.warning(f"Could not parse benchmark result: {result_path}")
        break
    st.subheader("Structured event log")
    for path in (Path("artifacts/m7_runs/dashboard/activity_events.csv"),
                 Path("artifacts/m7_runs/dashboard/activity_events.jsonl"),
                 Path("artifacts/m7_runs/dashboard/session_events.jsonl")):
        if path.exists():
            st.download_button(path.name, path.read_bytes(), file_name=path.name)
