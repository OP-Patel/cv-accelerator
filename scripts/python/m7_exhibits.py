#!/usr/bin/env python3
"""High-signal technical exhibits for the M7 Streamlit console."""

from __future__ import annotations

import streamlit.components.v1 as components


_BASE_STYLE = r"""
* { box-sizing: border-box; }
:root {
  --bg: #060608;
  --surface: #0b0b0e;
  --surface-2: #111116;
  --line: #2b2b33;
  --line-strong: #52525b;
  --ink: #f4f4f5;
  --muted: #a1a1aa;
  --accent: #ef4444;
  --accent-soft: #1a0b0d;
  --good: #3b82f6;
  --blue: #3b82f6;
}
html, body { margin: 0; background: transparent; color: var(--ink); }
html { scrollbar-color: var(--blue) var(--bg); scrollbar-width: thin; }
::-webkit-scrollbar { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: var(--bg); }
::-webkit-scrollbar-thumb { background: var(--blue); border: 2px solid var(--bg); }
body { font: 14px/1.5 "Cascadia Mono", "Cascadia Code", Consolas, ui-monospace, monospace; }
.exhibit {
  background: var(--bg);
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
  padding: 30px clamp(18px, 3.5vw, 48px);
  overflow: hidden;
}
.eyebrow {
  color: var(--accent);
  font: 750 11px/1.2 ui-monospace, "Cascadia Code", monospace;
  letter-spacing: .14em;
  text-transform: uppercase;
}
h2 { margin: 9px 0 8px; font-size: clamp(25px, 3vw, 40px); line-height: 1.05; letter-spacing: -.045em; }
.lede { max-width: 900px; margin: 0; color: var(--muted); line-height: 1.6; }
.mono { font-family: ui-monospace, "Cascadia Code", monospace; }
.accent { color: var(--accent); }
.good { color: var(--blue); }
"""


def render_system_pipeline() -> None:
    """Show the physical live path and the distinct 32-lane benchmark fork."""
    components.html(
        f"""
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><style>
{_BASE_STYLE}
.domains {{ display:grid; grid-template-columns: 1fr 1.25fr 1.4fr 1.25fr 1fr; gap:8px; margin:24px 0 8px; }}
.domain {{ color:var(--muted); font:700 10px/1.2 ui-monospace,monospace; text-transform:uppercase; letter-spacing:.08em; }}
.domain:nth-child(3) {{ color:var(--accent); }}
.flow {{ display:grid; grid-template-columns: 1fr 1.25fr 1.4fr 1.25fr 1fr; gap:8px; position:relative; }}
.node {{
  min-height:144px; padding:15px; border-top:2px solid var(--line-strong);
  background:var(--surface);
  position:relative; transition:background .2s ease,border-color .2s ease,transform .2s ease;
}}
.node:hover {{ background:var(--accent-soft); border-color:var(--accent); transform:translateY(-3px); }}
.node::after {{ content:"→"; position:absolute; right:-9px; top:54px; z-index:3; color:var(--accent); font:700 18px/1 monospace; }}
.node:last-child::after {{ display:none; }}
.num {{ color:var(--muted); font:700 10px/1.2 ui-monospace,monospace; }}
.node b {{ display:block; margin:20px 0 7px; font-size:16px; line-height:1.15; }}
.node span {{ color:var(--muted); font-size:12px; line-height:1.45; }}
.node code {{ display:block; margin-top:10px; color:#8bb7ff; font:700 10px/1.35 ui-monospace,monospace; }}
.pulse {{ position:absolute; top:0; left:-12px; width:8px; height:8px; background:var(--blue); animation:travel 5.5s linear infinite; }}
@keyframes travel {{ from{{left:0}} to{{left:calc(100% - 8px)}} }}
.fork {{ display:grid; grid-template-columns:1fr 1fr; gap:24px; margin-top:22px; padding-top:20px; border-top:1px solid var(--line); }}
.path {{ display:grid; grid-template-columns:105px 1fr; gap:16px; align-items:start; }}
.path-tag {{ color:var(--ink); font:800 11px/1.25 ui-monospace,monospace; text-transform:uppercase; }}
.path-tag i {{ display:inline-block; width:7px; height:7px; background:var(--blue); margin-right:7px; }}
.path.benchmark .path-tag i {{ background:var(--accent); }}
.path p {{ color:var(--muted); font-size:12px; margin:0; }}
.path strong {{ color:var(--ink); }}
.path-readout {{ margin-top:7px; color:var(--muted); font:700 9px/1.2 ui-monospace,monospace; letter-spacing:.06em; }}
.live-rail {{ height:10px; border:1px solid var(--line); margin-top:13px; position:relative; overflow:hidden; background:#09090b; }}
.live-rail::after {{ content:""; position:absolute; top:1px; bottom:1px; left:0; width:10px; background:var(--blue); animation:live-pixel 2.2s linear infinite; }}
@keyframes live-pixel {{ from{{left:0}} to{{left:calc(100% - 10px)}} }}
.lane-bank {{ display:grid; grid-template-columns:repeat(16,1fr); gap:3px; margin-top:13px; }}
.lane-bank i {{ height:10px; display:block; background:#18181b; border-top:2px solid #7f1d1d; animation:test-batch 1.45s steps(1,end) infinite; }}
@keyframes test-batch {{ 0%,100%{{background:#18181b;border-color:#7f1d1d}} 42%,68%{{background:var(--accent);border-color:#ff8b8b}} }}
@media(max-width:760px) {{
  .domains {{ display:none; }} .flow {{ grid-template-columns:1fr; }}
  .node {{ min-height:105px; }} .node::after {{ content:"↓"; right:50%; top:auto; bottom:-13px; }}
  .fork {{ grid-template-columns:1fr; }}
}}
</style></head><body>
<section class="exhibit">
  <div class="eyebrow">System map / verified physical path</div>
  <h2>Implemented camera-to-host data path</h2>
  <p class="lede">Each stage is implemented in custom RTL or strict host code. The live path and the separate 32-lane benchmark path are shown explicitly.</p>
  <div class="domains"><div>Sensor domain</div><div>PCLK → 100 MHz</div><div>200 MHz core</div><div>Ethernet domains</div><div>Host</div></div>
  <div class="flow">
    <div class="pulse"></div>
    <div class="node"><div class="num">01 / SENSOR</div><b>OV7670</b><span>Direct 8-bit DVP camera. SCCB register initialization, 24 MHz XCLK, QVGA RGB565.</span><code>320 × 240 · D[7:0]</code></div>
    <div class="node"><div class="num">02 / CAPTURE</div><b>Decode + cross</b><span>Byte pairing, HREF/VSYNC checks, RGB565 capture, asynchronous FIFO into system logic.</span><code>PCLK → 100 MHz</code></div>
    <div class="node"><div class="num">03 / COMPUTE</div><b>Spatial Sobel</b><span>Grayscale, two BRAM rows, a 3×3 window, parallel Gx/Gy, saturation, optional threshold.</span><code>1 px / cycle · 200 MHz</code></div>
    <div class="node"><div class="num">04 / TRANSPORT</div><b>Packet + protect</b><span>32 KiB stream FIFO, 1,024-byte chunks, M5CV metadata, payload CRC32, UDP and Ethernet FCS.</span><code>74 or 75 packets / frame</code></div>
    <div class="node"><div class="num">05 / HOST</div><b>Reject or render</b><span>Python checks dimensions, sequence, indexes, offsets, flags, length and CRC before display.</span><code>192.168.10.2 → .1</code></div>
  </div>
  <div class="fork">
    <div class="path live"><div class="path-tag"><i></i> Live path</div><div><p><strong>One physical lane</strong> processes the real camera stream. The sensor—not the core—sets the validated 7.5, 15 or 30 FPS cadence.</p><div class="live-rail"></div><div class="path-readout">1 LANE · CONTINUOUS SENSOR-PACED PIXELS</div></div></div>
    <div class="path benchmark"><div class="path-tag"><i></i> Test path</div><div><p><strong>32 independent lanes</strong> process deterministic frames only during the controlled benchmark: 81,380 requested frames/s measured.</p><div class="lane-bank">{''.join('<i></i>' for _ in range(32))}</div><div class="path-readout">32 LANES · FRAME-PARALLEL TEST BATCH</div></div></div>
  </div>
</section></body></html>
""",
        height=570,
        scrolling=True,
    )


def render_compute_comparison() -> None:
    """Put the exact OpenCV control beside the equivalent FPGA dataflow."""
    components.html(
        f"""
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><style>
{_BASE_STYLE}
.compare {{ display:grid; grid-template-columns:1fr 1fr; gap:1px; background:var(--line); margin-top:24px; border:1px solid var(--line); }}
.side {{ background:var(--bg); padding:22px; min-height:430px; }}
.side-head {{ display:flex; justify-content:space-between; align-items:baseline; gap:12px; border-bottom:1px solid var(--line); padding-bottom:14px; }}
.side-head b {{ font-size:20px; letter-spacing:-.03em; }}
.side-head span {{ color:var(--muted); font:700 10px/1.2 ui-monospace,monospace; text-transform:uppercase; letter-spacing:.08em; }}
pre {{ margin:18px 0 15px; padding:16px; background:#050506; border-left:2px solid var(--blue); overflow:auto; color:#d4d4d8; font:12px/1.65 ui-monospace,"Cascadia Code",monospace; }}
.kw {{ color:#8bb7ff; }} .fn {{ color:#8bb7ff; }} .cm {{ color:#71717a; }}
.steps {{ display:grid; gap:0; }}
.step {{ display:grid; grid-template-columns:28px 1fr auto; gap:10px; align-items:center; padding:10px 0; border-top:1px solid var(--line); color:var(--muted); font-size:12px; }}
.step i {{ width:7px; height:7px; background:#71717a; margin-left:5px; }}
.step b {{ color:var(--ink); font-size:12px; }}
.step code {{ color:var(--muted); font-size:10px; }}
.hardware {{ position:relative; display:grid; grid-template-columns:1fr 1fr; gap:8px; margin:18px 0; }}
.block {{ min-height:66px; display:flex; flex-direction:column; justify-content:center; padding:10px; border:1px solid var(--line); background:var(--surface); color:var(--muted); font-size:11px; transition:.2s ease; }}
.block:hover {{ border-color:var(--accent); background:var(--accent-soft); transform:translateY(-2px); }}
.block b {{ color:var(--ink); font-size:13px; margin-bottom:2px; }}
.block.parallel {{ border-color:var(--blue); }}
.lanes {{ display:grid; grid-template-columns:repeat(16,1fr); gap:3px; margin:11px 0 15px; }}
.lane {{ height:20px; background:#101b2f; border-top:2px solid var(--blue); animation:wake .7s ease both; animation-delay:calc(var(--n) * 20ms); }}
@keyframes wake {{ from{{opacity:0;transform:scaleY(.2)}} }}
.result {{ display:grid; grid-template-columns:1fr auto; gap:20px; align-items:end; padding-top:15px; border-top:1px solid var(--line); }}
.result-label {{ color:var(--muted); font:700 10px/1.2 ui-monospace,monospace; letter-spacing:.08em; text-transform:uppercase; }}
.result strong {{ display:block; margin-top:4px; color:var(--ink); font-size:30px; letter-spacing:-.05em; }}
.result .win strong {{ color:#8bb7ff; }}
.bars {{ margin-top:20px; }}
.bar {{ display:grid; grid-template-columns:96px 1fr 110px; align-items:center; gap:10px; margin:9px 0; color:var(--muted); font-size:11px; }}
.track {{ height:10px; background:#202027; overflow:hidden; }}
.fill {{ height:100%; transform-origin:left; animation:grow .9s ease both; }}
.fill.cpu {{ width:100%; background:#71717a; }} .fill.fpga {{ width:17.42%; background:var(--blue); }}
@keyframes grow {{ from{{transform:scaleX(0)}} }}
.contract {{ display:grid; grid-template-columns:repeat(4,1fr); border-top:1px solid var(--line); margin-top:22px; }}
.proof {{ padding:15px 14px 0 0; color:var(--muted); font-size:11px; }}
.proof b {{ display:block; color:#8bb7ff; font:800 12px/1.2 ui-monospace,monospace; margin-bottom:4px; }}
.caveat {{ margin-top:18px; padding:13px 15px; border-left:2px solid var(--accent); color:var(--muted); background:var(--accent-soft); font-size:12px; }}
@media(max-width:760px) {{ .compare{{grid-template-columns:1fr}} .contract{{grid-template-columns:1fr 1fr}} .side{{min-height:0}} }}
</style></head><body>
<section class="exhibit">
  <div class="eyebrow">Execution model / same Sobel result</div>
  <h2>Controlled Sobel implementation comparison</h2>
  <p class="lede">The comparison does not use a slow Python loop. It uses OpenCV's optimized, single-threaded C++ kernel and charges both sides for the same cropped, saturated 3×3 Sobel output.</p>
  <div class="compare">
    <div class="side">
      <div class="side-head"><b>OpenCV on CPU</b><span>general-purpose instructions</span></div>
      <pre><span class="cm"># exact benchmark control</span>
cv2.<span class="fn">setNumThreads</span>(1)
gx, gy = cv2.<span class="fn">spatialGradient</span>(gray, ksize=3)
edge = cv2.<span class="fn">add</span>(
    cv2.<span class="fn">convertScaleAbs</span>(gx),
    cv2.<span class="fn">convertScaleAbs</span>(gy),
)[1:-1, 1:-1]</pre>
      <div class="steps">
        <div class="step"><i></i><b>Fetch neighborhoods</b><code>cache / RAM</code></div>
        <div class="step"><i></i><b>Issue gradient instructions</b><code>CPU core</code></div>
        <div class="step"><i></i><b>Absolute value + add</b><code>more instructions</code></div>
        <div class="step"><i></i><b>Crop and return</b><code>318 × 238</code></div>
      </div>
      <div class="result"><div><div class="result-label">median kernel time</div><strong>0.070522 ms</strong></div><div class="result-label">14,180 fps</div></div>
    </div>
    <div class="side">
      <div class="side-head"><b>SystemVerilog on FPGA</b><span>spatial dataflow circuit</span></div>
      <div class="hardware">
        <div class="block"><b>Two BRAM rows</b>previous pixels stay beside compute</div>
        <div class="block"><b>3×3 shift window</b>nine values exposed together</div>
        <div class="block parallel"><b>Gx adders</b>exist physically</div>
        <div class="block parallel"><b>Gy adders</b>run at the same time</div>
        <div class="block"><b>Saturate / threshold</b>fixed pipeline stages</div>
        <div class="block"><b>CRC metrics</b>correctness in hardware</div>
      </div>
      <div class="result-label">32 independent benchmark lanes @ 200 MHz</div>
      <div class="lanes">{''.join(f'<i class="lane" style="--n:{n}"></i>' for n in range(32))}</div>
      <div class="result"><div class="win"><div class="result-label">physical frame time</div><strong>0.012288 ms</strong></div><div class="result-label">81,380 fps</div></div>
    </div>
  </div>
  <div class="bars">
    <div class="bar"><span>OpenCV CPU</span><div class="track"><div class="fill cpu"></div></div><b>100% time</b></div>
    <div class="bar"><span>FPGA core</span><div class="track"><div class="fill fpga"></div></div><b>17.42% time</b></div>
  </div>
  <div class="contract">
    <div class="proof"><b>01 · SAME INPUT</b>32 deterministic 320×240 patterns</div>
    <div class="proof"><b>02 · SAME OUTPUT</b>318×238 saturated L1 Sobel</div>
    <div class="proof"><b>03 · REPEATED</b>5 independent runs × 1,000 frames</div>
    <div class="proof"><b>04 · BIT-EXACT</b>CRC32 0x9e562313 on both</div>
  </div>
  <div class="caveat"><strong>Read the number correctly:</strong> 5.739× is controlled Sobel compute throughput. The live path uses one lane and is capped by the OV7670 at 30 FPS; network and UI rates are reported separately.</div>
</section></body></html>
""",
        height=900,
        scrolling=True,
    )


def render_wiring_map() -> None:
    """Interactive camera pin map plus the board-to-host Ethernet path."""
    rows = (
        ("timing", "PLK", "JB1", "E15", "cam_pclk", "Camera → FPGA"),
        ("timing", "VS", "JB2", "E16", "cam_vsync", "Camera → FPGA"),
        ("timing", "HS", "JB3", "D15", "cam_href", "Camera → FPGA"),
        ("timing", "XLK", "JB4", "C15", "cam_xclk", "FPGA → Camera"),
        ("control", "SCL", "JB7", "J17", "cam_sio_c", "FPGA → Camera"),
        ("control", "SDA", "JB8", "J18", "cam_sio_d", "Bidirectional"),
        ("control", "RET", "JB9", "K15", "cam_reset_n", "FPGA → Camera"),
        ("control", "PWDN", "JB10", "J15", "cam_pwdn", "FPGA → Camera"),
        ("data", "D[0:7]", "JC1–4,7–10", "U12…U13", "cam_d[7:0]", "Camera → FPGA"),
        ("power", "3.3V", "JB6", "—", "module power", "Board → Camera"),
        ("power", "DGND", "JB5", "—", "ground", "Common"),
    )
    row_html = "".join(
        f'<div class="wire" data-group="{group}"><b>{camera}</b><span>{header}</span>'
        f'<span>{pin}</span><code>{rtl}</code><em>{direction}</em></div>'
        for group, camera, header, pin, rtl, direction in rows
    )
    components.html(
        f"""
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><style>
{_BASE_STYLE}
.filters {{ display:flex; gap:7px; flex-wrap:wrap; margin:20px 0 13px; }}
.filter {{ border:1px solid var(--line); background:transparent; color:var(--muted); padding:7px 11px; cursor:pointer; font:700 10px/1.2 ui-monospace,monospace; text-transform:uppercase; }}
.filter:hover,.filter.active {{ color:#ffffff; background:var(--blue); border-color:var(--blue); }}
.wire-head,.wire {{ display:grid; grid-template-columns:.65fr .9fr .75fr 1.2fr 1fr; gap:12px; align-items:center; }}
.wire-head {{ color:var(--muted); font:700 9px/1.2 ui-monospace,monospace; letter-spacing:.08em; text-transform:uppercase; padding:0 11px 8px; }}
.wire {{ min-height:39px; border-top:1px solid var(--line); padding:8px 11px; transition:opacity .2s ease,background .2s ease; }}
.wire:hover {{ background:var(--accent-soft); }} .wire.dim {{ opacity:.14; }}
.wire b {{ color:#8bb7ff; font:800 12px/1 ui-monospace,monospace; }}
.wire span,.wire em {{ color:var(--muted); font-size:11px; font-style:normal; }}
.wire code {{ color:var(--ink); font:11px/1.2 ui-monospace,monospace; }}
.physical {{ display:grid; grid-template-columns:1fr auto 1fr auto 1fr; align-items:center; gap:12px; margin-top:26px; padding-top:22px; border-top:1px solid var(--line); }}
.device {{ min-height:93px; border-top:2px solid var(--line-strong); padding:13px; background:var(--surface); }}
.device b {{ display:block; font-size:14px; margin:3px 0 6px; }} .device span {{ color:var(--muted); font-size:11px; }}
.arrow {{ color:var(--accent); font:800 18px/1 monospace; }}
.network {{ margin-top:16px; display:grid; grid-template-columns:1fr 1fr; gap:18px; }}
.network p {{ margin:0; color:var(--muted); font-size:11px; }} .network code {{ color:#8bb7ff; }}
.warning {{ margin-top:17px; color:var(--muted); font-size:11px; border-left:2px solid var(--accent); padding-left:12px; }}
@media(max-width:700px) {{ .wire-head{{display:none}} .wire{{grid-template-columns:.7fr 1fr 1fr}} .wire code,.wire em{{display:none}} .physical{{grid-template-columns:1fr}} .arrow{{transform:rotate(90deg);text-align:center}} .network{{grid-template-columns:1fr}} }}
</style></head><body>
<section class="exhibit">
  <div class="eyebrow">Physical interface / bench contract</div>
  <h2>OV7670 and Ethernet hardware connections</h2>
  <p class="lede">The camera is not USB. Sixteen signals are assigned directly across the Arty's JB and JC Pmod headers. Filter the reviewed pin map by function.</p>
  <div class="filters">
    <button class="filter active" data-filter="all">All</button><button class="filter" data-filter="data">Pixel bus</button>
    <button class="filter" data-filter="timing">Timing</button><button class="filter" data-filter="control">SCCB / control</button><button class="filter" data-filter="power">Power</button>
  </div>
  <div class="wire-head"><span>Camera label</span><span>Arty header</span><span>FPGA pin</span><span>RTL port</span><span>Direction</span></div>
  <div id="wires">{row_html}</div>
  <div class="physical">
    <div class="device"><div class="eyebrow">On-board PHY</div><b>TI DP83848J</b><span>Custom MDIO bring-up + 4-bit MII RX/TX RTL</span></div><div class="arrow">→</div>
    <div class="device"><div class="eyebrow">Physical link</div><b>10/100 Ethernet</b><span>Direct cable; ARP, IPv4, UDP and FCS generated in logic</span></div><div class="arrow">→</div>
    <div class="device"><div class="eyebrow">Validation host</div><b>Windows adapter</b><span>Strict Python receiver, control client and Streamlit UI</span></div>
  </div>
  <div class="network"><p><code>FPGA</code> 02:00:00:00:00:01 · 192.168.10.2 · UDP 4000/4001</p><p><code>HOST</code> 192.168.10.1/24 · gateway blank · learned return port</p></div>
  <div class="warning">Power down before moving camera jumpers. The unbranded module has an unresolved I/O-voltage/level-shifting risk documented in the hardware contract; short wiring and the reviewed pin orientation matter.</div>
</section>
<script>
const filters=[...document.querySelectorAll('.filter')]; const wires=[...document.querySelectorAll('.wire')];
filters.forEach(button=>button.addEventListener('click',()=>{{
  filters.forEach(item=>item.classList.toggle('active',item===button));
  const group=button.dataset.filter; wires.forEach(row=>row.classList.toggle('dim',group!=='all'&&row.dataset.group!==group));
}}));
</script></body></html>
""",
        height=1000,
        scrolling=True,
    )


def render_resource_budget() -> None:
    """Render routed utilization as a compact expansion budget."""
    components.html(
        f"""
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><style>
{_BASE_STYLE}
.budget {{ display:grid; grid-template-columns:repeat(4,1fr); gap:20px; margin-top:22px; }}
.meter {{ border-top:1px solid var(--line); padding-top:12px; }}
.meter-head {{ display:flex; justify-content:space-between; gap:8px; align-items:baseline; }}
.meter b {{ font-size:15px; }} .meter span {{ color:var(--muted); font:10px/1.2 ui-monospace,monospace; }}
.track {{ height:8px; background:#202027; margin:12px 0 8px; overflow:hidden; }}
.fill {{ height:100%; width:var(--used); background:var(--blue); animation:grow .8s ease both; transform-origin:left; }}
@keyframes grow {{ from{{transform:scaleX(0)}} }}
.meter p {{ color:var(--muted); font-size:11px; margin:0; }}
.note {{ margin-top:20px; color:var(--muted); font-size:12px; border-left:2px solid var(--accent); padding-left:12px; }}
@media(max-width:700px) {{ .budget{{grid-template-columns:1fr 1fr}} }}
</style></head><body><section class="exhibit">
<div class="eyebrow">Routed implementation / resource usage</div><h2>Post-route utilization and available resources</h2>
<p class="lede">The current design deliberately implements Sobel with LUT adders. A small quantized CNN can target the unused multiplier fabric, but routing, memory bandwidth and timing still need a fresh implementation run.</p>
<div class="budget">
  <div class="meter"><div class="meter-head"><b>LUTs</b><span>17,731 / 63,400</span></div><div class="track"><div class="fill" style="--used:27.97%"></div></div><p>72.03% unallocated</p></div>
  <div class="meter"><div class="meter-head"><b>Registers</b><span>35,303 / 126,800</span></div><div class="track"><div class="fill" style="--used:27.84%"></div></div><p>72.16% unallocated</p></div>
  <div class="meter"><div class="meter-head"><b>BRAM</b><span>47 / 135 tiles</span></div><div class="track"><div class="fill" style="--used:34.81%"></div></div><p>65.19% unallocated</p></div>
  <div class="meter"><div class="meter-head"><b>DSP48</b><span>0 / 240</span></div><div class="track"><div class="fill" style="--used:0%"></div></div><p>All 240 currently free</p></div>
</div><div class="note">Headroom is not a fit guarantee. Preserve a margin for the AXI/stream wrapper, FIFOs and post-route timing; estimate first, synthesize second, then validate on the physical camera path.</div>
</section></body></html>
""",
        height=390,
        scrolling=True,
    )
