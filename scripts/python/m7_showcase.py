#!/usr/bin/env python3
"""Self-contained interactive exhibits used by the M7 Streamlit console."""

from __future__ import annotations

import streamlit.components.v1 as components


_SHARED_STYLE = """
  :root {
    color-scheme: dark;
    --ink: #f4f4f5;
    --muted: #a1a1aa;
    --surface: #060608;
    --surface-2: #111116;
    --line: #2b2b33;
    --accent: #ef4444;
    --accent-soft: #1a0b0d;
    --good: #3b82f6;
    --blue: #3b82f6;
    --warn: #ef4444;
  }
  * { box-sizing: border-box; }
  html { scrollbar-color: var(--blue) var(--surface); scrollbar-width: thin; }
  ::-webkit-scrollbar { width: 10px; height: 10px; }
  ::-webkit-scrollbar-track { background: var(--surface); }
  ::-webkit-scrollbar-thumb { background: var(--blue); border: 2px solid var(--surface); }
  body {
    margin: 0;
    background: transparent;
    color: var(--ink);
    font-family: "Cascadia Mono", "Cascadia Code", Consolas, ui-monospace, monospace;
  }
  button, select, input { font: inherit; }
  .exhibit {
    border: 1px solid var(--line);
    border-radius: 0;
    background: var(--surface);
    padding: 22px;
    overflow: hidden;
  }
  .eyebrow {
    color: var(--accent);
    font: 700 11px/1.2 ui-monospace, "Cascadia Code", monospace;
    letter-spacing: .14em;
    text-transform: uppercase;
  }
  h2 {
    margin: 8px 0 7px;
    font-size: clamp(22px, 3vw, 34px);
    line-height: 1.05;
    letter-spacing: -.035em;
  }
  .lede { color: var(--muted); line-height: 1.55; max-width: 840px; margin: 0; }
  .mono { font-family: ui-monospace, "Cascadia Code", monospace; }
  .good { color: var(--blue); }
  .accent { color: var(--accent); }
"""


def render_udp_explorer() -> None:
    """Render a click-to-explore representation of one camera UDP packet."""
    components.html(
        f"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
{_SHARED_STYLE}
  .toolbar {{
    display: flex;
    align-items: center;
    gap: 12px;
    margin: 18px 0 14px;
    flex-wrap: wrap;
  }}
  label {{ color: var(--muted); font-size: 13px; }}
  select {{
    color: var(--ink);
    background: var(--surface-2);
    border: 1px solid var(--line);
    border-radius: 0;
    padding: 8px 30px 8px 10px;
  }}
  .packet {{
    display: grid;
    grid-template-columns: 1.1fr 1.25fr .8fr 1.6fr 3.2fr .65fr;
    gap: 5px;
    min-height: 90px;
  }}
  .field {{
    position: relative;
    border: 1px solid var(--line);
    background: var(--surface-2);
    color: var(--ink);
    border-radius: 0;
    padding: 12px 9px;
    text-align: left;
    cursor: pointer;
    transition: transform .18s ease, border-color .18s ease, background .18s ease;
    overflow: hidden;
  }}
  .field::after {{
    content: "";
    position: absolute;
    inset: auto 0 0;
    height: 3px;
    background: var(--blue);
    transform: scaleX(0);
    transform-origin: left;
    transition: transform .2s ease;
  }}
  .field:hover {{ transform: translateY(-2px); border-color: var(--blue); }}
  .field.active {{ background: #101b2f; border-color: var(--blue); }}
  .field.active::after {{ transform: scaleX(1); }}
  .field strong {{ display:block; font-size: 13px; line-height: 1.2; }}
  .field small {{ color: var(--muted); font: 11px/1.3 ui-monospace, monospace; }}
  .detail {{
    margin-top: 14px;
    min-height: 122px;
    display: grid;
    grid-template-columns: 1.1fr 1.9fr;
    gap: 18px;
    padding: 17px;
    border-left: 3px solid var(--blue);
    background: var(--surface-2);
    border-radius: 0;
  }}
  .detail h3 {{ font-size: 17px; margin: 0 0 7px; }}
  .detail p {{ color: var(--muted); margin: 0; line-height: 1.5; font-size: 13px; }}
  .bytes {{ color: #8bb7ff; font: 700 27px/1 ui-monospace, monospace; margin-bottom: 8px; }}
  .contract {{
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 7px;
    margin-top: 15px;
  }}
  .check {{
    padding: 10px;
    border: 1px solid var(--line);
    border-radius: 0;
    color: var(--muted);
    font-size: 11px;
  }}
  .check b {{ display: block; color: #8bb7ff; font-size: 13px; margin-bottom: 3px; }}
  .math {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    margin-top: 14px;
    padding-top: 14px;
    border-top: 1px solid var(--line);
    color: var(--muted);
    font-size: 13px;
  }}
  .math strong {{ color: var(--ink); font-size: 18px; }}
  @media(max-width: 720px) {{
    .packet {{ grid-template-columns: repeat(3, 1fr); }}
    .detail {{ grid-template-columns: 1fr; }}
    .contract {{ grid-template-columns: repeat(2, 1fr); }}
    .math {{ align-items: flex-start; flex-direction: column; }}
  }}
</style>
</head>
<body>
<section class="exhibit">
  <div class="eyebrow">Protocol inspection / one packet</div>
  <h2>UDP packet and frame validation contract</h2>
  <p class="lede">Select a field. The FPGA emits bounded UDP datagrams; the host
  accepts a frame only after checking shape, ordering, offsets, flags, and every
  payload CRC.</p>
  <div class="toolbar">
    <label for="stream">Reassemble</label>
    <select id="stream">
      <option value="sobel">Sobel · 318 × 238</option>
      <option value="gray">Grayscale · 320 × 240</option>
    </select>
    <span class="mono" id="packetReadout"></span>
  </div>
  <div class="packet" id="packet">
    <button class="field" data-key="ethernet"><strong>Ethernet</strong><small>14 bytes</small></button>
    <button class="field" data-key="ipv4"><strong>IPv4</strong><small>20 bytes</small></button>
    <button class="field" data-key="udp"><strong>UDP</strong><small>8 bytes</small></button>
    <button class="field active" data-key="m5cv"><strong>M5CV header</strong><small>32 bytes</small></button>
    <button class="field" data-key="pixels"><strong>Pixel chunk</strong><small>≤ 1,024 bytes</small></button>
    <button class="field" data-key="fcs"><strong>FCS</strong><small>4 bytes</small></button>
  </div>
  <div class="detail">
    <div>
      <div class="bytes" id="detailBytes">32 B</div>
      <h3 id="detailTitle">Application header</h3>
      <p id="detailTag">The FPGA/host integrity contract.</p>
    </div>
    <p id="detailBody">Magic and version identify the protocol. Stream mode,
    start/last/discontinuity flags, frame sequence, packet index/count, pixel
    offset, payload length, dimensions, and CRC32 make every chunk independently
    checkable.</p>
  </div>
  <div class="contract">
    <div class="check"><b>01 · Shape</b>318×238 or 320×240</div>
    <div class="check"><b>02 · Order</b>sequence + packet index</div>
    <div class="check"><b>03 · Placement</b>pixel offset + length</div>
    <div class="check"><b>04 · Integrity</b>CRC32 per payload</div>
    <div class="check"><b>05 · Completion</b>all packets + last flag</div>
  </div>
  <div class="math">
    <span id="frameMath">75,684 bytes ÷ 1,024 → 74 packets; final chunk 932 bytes</span>
    <strong id="wireMath">1,098 B max before Ethernet FCS</strong>
  </div>
</section>
<script>
const details = {{
  ethernet: {{
    bytes: "14 B", title: "Ethernet envelope", tag: "Direct, local, deterministic.",
    body: "Destination and source MAC addresses plus EtherType 0x0800. The FPGA learns the host address from the control request and replies directly over the cable."
  }},
  ipv4: {{
    bytes: "20 B", title: "IPv4 header", tag: "192.168.10.2 → 192.168.10.1.",
    body: "A fixed, non-fragmented IPv4 header carries total length, an identification derived from frame and packet indexes, protocol 17 for UDP, and a computed header checksum."
  }},
  udp: {{
    bytes: "8 B", title: "UDP transport", tag: "Small protocol, bounded latency.",
    body: "The FPGA sends from control port 4001 back to the host port that opened the session. UDP avoids connection state; the application header restores the integrity evidence video needs."
  }},
  m5cv: {{
    bytes: "32 B", title: "Application header", tag: "The FPGA/host integrity contract.",
    body: "Magic and version identify the protocol. Stream mode, start/last/discontinuity flags, frame sequence, packet index/count, pixel offset, payload length, dimensions, and CRC32 make every chunk independently checkable."
  }},
  pixels: {{
    bytes: "≤1,024 B", title: "Pixel payload", tag: "One byte per grayscale or Sobel pixel.",
    body: "Chunks are placed at packet_index × 1,024. The receiver rejects oversized, overlapping, truncated, or misplaced payloads before a frame can appear in the live view."
  }},
  fcs: {{
    bytes: "4 B", title: "Ethernet frame check sequence", tag: "The link-level safety net.",
    body: "The Ethernet transmitter appends the standard reflected CRC-32 over the frame. This is separate from the payload CRC stored inside M5CV, so corruption is checked at two layers."
  }}
}};
const fields = [...document.querySelectorAll(".field")];
function activate(key) {{
  fields.forEach(el => el.classList.toggle("active", el.dataset.key === key));
  const d = details[key];
  document.getElementById("detailBytes").textContent = d.bytes;
  document.getElementById("detailTitle").textContent = d.title;
  document.getElementById("detailTag").textContent = d.tag;
  document.getElementById("detailBody").textContent = d.body;
}}
fields.forEach(el => el.addEventListener("click", () => activate(el.dataset.key)));
function streamMath() {{
  const gray = document.getElementById("stream").value === "gray";
  document.getElementById("packetReadout").textContent =
    gray ? "75 packets / frame" : "74 packets / frame";
  document.getElementById("frameMath").textContent = gray
    ? "76,800 bytes ÷ 1,024 → 75 full packets"
    : "75,684 bytes ÷ 1,024 → 74 packets; final chunk 932 bytes";
}}
document.getElementById("stream").addEventListener("change", streamMath);
streamMath();
</script>
</body>
</html>
""",
        height=650,
        scrolling=True,
    )


def render_sobel_walkthrough() -> None:
    """Render a step-through Sobel computation and measured latency comparison."""
    components.html(
        f"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
{_SHARED_STYLE}
  .walk-grid {{
    display: grid;
    grid-template-columns: .9fr 1.25fr 1fr;
    gap: 14px;
    margin-top: 18px;
  }}
  .panel {{
    background: var(--surface-2);
    border: 1px solid var(--line);
    border-radius: 0;
    padding: 15px;
    min-height: 275px;
  }}
  .panel h3 {{ margin: 0 0 11px; font-size: 14px; color: var(--muted); font-weight: 600; }}
  .pixels, .kernel {{
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 5px;
  }}
  .pixel, .kernel span {{
    aspect-ratio: 1;
    border: 1px solid #3f3f46;
    border-radius: 0;
    display: grid;
    place-items: center;
    font: 700 15px/1 ui-monospace, monospace;
    transition: all .28s ease;
  }}
  .pixel {{ background: rgb(var(--v), var(--v), var(--v)); color: #fff; text-shadow: 0 1px 3px #000; }}
  .pixel.hot {{ border-color: var(--blue); transform: scale(.94); }}
  .kernel span {{ aspect-ratio: auto; min-height: 34px; background:#09090b; color:var(--ink); }}
  .kernels {{ display:grid; grid-template-columns: 1fr 1fr; gap:10px; }}
  .kernel-label {{ font: 700 11px/1 ui-monospace, monospace; color:#8bb7ff; margin: 0 0 6px; }}
  .equation {{
    margin-top: 11px;
    padding: 11px;
    border-radius: 0;
    background: #09090b;
    font: 12px/1.55 ui-monospace, monospace;
    color: var(--muted);
  }}
  .equation strong {{ color: var(--ink); }}
  .output {{
    height: 94px;
    display:grid;
    place-items:center;
    margin: 12px 0;
    border: 1px solid var(--line);
    border-radius: 0;
    background:#09090b;
    position:relative;
    overflow:hidden;
  }}
  .output::before {{
    content:"";
    position:absolute;
    top:0;
    bottom:0;
    left:0;
    width:2px;
    background:var(--blue);
  }}
  .output.scan::before {{ animation: scan .7s ease; }}
  @keyframes scan {{ from {{ left:0; }} to {{ left:100%; }} }}
  .output-value {{ font: 800 42px/1 ui-monospace, monospace; }}
  .pipeline {{ display:grid; gap:7px; }}
  .stage {{
    display:flex; align-items:center; gap:9px;
    padding:8px 10px;
    border:1px solid var(--line); border-radius:0;
    color:var(--muted); font-size:12px;
    transition:all .25s ease;
  }}
  .stage i {{
    width:7px; height:7px; background:#52525b;
  }}
  .stage.done {{ color:var(--ink); border-color:var(--blue); }}
  .stage.done i {{ background:var(--blue); }}
  .stage.active {{ color:var(--ink); border-color:var(--accent); background:var(--accent-soft); }}
  .stage.active i {{ background:var(--accent); }}
  .controls {{
    display:flex; align-items:center; gap:8px; margin-top:14px; padding:8px 0;
    flex-wrap:wrap; position:sticky; top:0; z-index:5; background:var(--surface);
    border-bottom:1px solid var(--line);
  }}
  .control {{
    border:1px solid var(--line); border-radius:0; background:#111116; color:var(--ink);
    padding:8px 12px; cursor:pointer;
  }}
  .control.primary {{ border-color:var(--blue); background:var(--blue); color:#ffffff; font-weight:800; }}
  .control:hover {{ transform:translateY(-1px); }}
  .step-copy {{ margin-left:auto; color:var(--muted); font-size:12px; }}
  .compare {{
    display:grid; grid-template-columns:1fr 1fr; gap:20px;
    margin-top:15px; padding-top:15px; border-top:1px solid var(--line);
  }}
  .bar-row {{ display:grid; grid-template-columns:82px 1fr 88px; gap:9px; align-items:center; margin:8px 0; font-size:12px; }}
  .track {{ height:9px; background:#202027; border-radius:0; overflow:hidden; }}
  .fill {{ height:100%; border-radius:0; background:#71717a; transform-origin:left; animation:grow .8s ease both; }}
  .fill.fpga {{ width:17.42%; background:var(--blue); }}
  .fill.cpu {{ width:100%; }}
  @keyframes grow {{ from {{ transform:scaleX(0); }} }}
  .proof {{
    border-left:2px solid var(--blue); padding-left:13px; color:var(--muted);
    font-size:12px; line-height:1.5;
  }}
  .proof strong {{ display:block; color:#8bb7ff; font-size:23px; }}
  input[type=range] {{ accent-color:var(--blue); width:120px; }}
  @media(max-width: 780px) {{
    .walk-grid {{ grid-template-columns:1fr; }}
    .compare {{ grid-template-columns:1fr; }}
    .step-copy {{ width:100%; margin:0; }}
  }}
</style>
</head>
<body>
<section class="exhibit">
  <div class="eyebrow">Computation inspection / one output pixel</div>
  <h2>One-pixel Sobel calculation and pipeline stages</h2>
  <p class="lede">Step through the same saturating <span class="mono">|Gx| + |Gy|</span>
  operation used by both implementations. The FPGA keeps the line buffers,
  window and arithmetic in dedicated hardware; the controlled benchmark uses
  32 independent lanes.</p>
  <div class="walk-grid">
    <div class="panel">
      <h3>3 × 3 grayscale window</h3>
      <div class="pixels" id="pixels">
        <div class="pixel" style="--v:12">12</div><div class="pixel" style="--v:18">18</div><div class="pixel" style="--v:22">22</div>
        <div class="pixel" style="--v:15">15</div><div class="pixel" style="--v:20">20</div><div class="pixel" style="--v:210">210</div>
        <div class="pixel" style="--v:13">13</div><div class="pixel" style="--v:17">17</div><div class="pixel" style="--v:220">220</div>
      </div>
      <div class="equation">Dark values on the left, bright values on the right.
      That local contrast is the vertical edge we want to expose.</div>
    </div>
    <div class="panel">
      <h3>Parallel Sobel arithmetic</h3>
      <div class="kernels">
        <div><div class="kernel-label">GX</div><div class="kernel">
          <span>-1</span><span>0</span><span>1</span><span>-2</span><span>0</span><span>2</span><span>-1</span><span>0</span><span>1</span>
        </div></div>
        <div><div class="kernel-label">GY</div><div class="kernel">
          <span>1</span><span>2</span><span>1</span><span>0</span><span>0</span><span>0</span><span>-1</span><span>-2</span><span>-1</span>
        </div></div>
      </div>
      <div class="equation">
        Gx = <strong>607</strong> · Gy = <strong>−197</strong><br>
        |607| + |−197| = 804 → saturate to <strong>255</strong>
      </div>
    </div>
    <div class="panel">
      <h3>Output and threshold</h3>
      <div class="output" id="output"><span class="output-value" id="outputValue">—</span></div>
      <label class="mono">threshold <span id="thresholdReadout">96</span></label><br>
      <input id="threshold" type="range" min="0" max="255" value="96">
      <div class="equation" id="thresholdCopy">Advance to see the edge decision.</div>
    </div>
  </div>
  <div class="controls">
    <button class="control" id="reset">Reset</button>
    <button class="control primary" id="next">Next stage</button>
    <button class="control" id="auto">Auto play</button>
    <span class="step-copy" id="stepCopy">Ready · camera presents RGB565</span>
  </div>
  <div class="pipeline" id="pipeline">
    <div class="stage" data-stage="0"><i></i>RGB565 → 8-bit grayscale</div>
    <div class="stage" data-stage="1"><i></i>BRAM retains two prior image rows</div>
    <div class="stage" data-stage="2"><i></i>Shift registers form the 3 × 3 window</div>
    <div class="stage" data-stage="3"><i></i>Gx and Gy adders run in parallel</div>
    <div class="stage" data-stage="4"><i></i>Magnitude saturates; optional threshold applies</div>
    <div class="stage" data-stage="5"><i></i>Result joins a CRC-checked UDP frame</div>
  </div>
  <div class="compare">
    <div>
      <div class="eyebrow">Measured core time · lower is better</div>
      <div class="bar-row"><span>OpenCV</span><div class="track"><div class="fill cpu"></div></div><b>0.070522 ms</b></div>
      <div class="bar-row"><span>FPGA</span><div class="track"><div class="fill fpga"></div></div><b>0.012288 ms</b></div>
    </div>
    <div class="proof"><strong>5.739×</strong>physical FPGA counters versus
    single-thread OpenCV, with the same deterministic inputs and matching
    combined output CRC <span class="mono">0x9e562313</span>.</div>
  </div>
</section>
<script>
const copies = [
  "Convert · RGB565 becomes one luminance byte",
  "Remember · two BRAM line buffers make old rows local",
  "Window · nine neighbors are available together",
  "Compute · Gx and Gy run in dedicated adders",
  "Decide · 804 saturates to 255, then threshold applies",
  "Package · output is sequenced and protected by CRC32"
];
let step = -1;
let timer = null;
const stages = [...document.querySelectorAll(".stage")];
const pixels = [...document.querySelectorAll(".pixel")];
const output = document.getElementById("output");
function render() {{
  stages.forEach((el, i) => {{
    el.classList.toggle("done", i < step);
    el.classList.toggle("active", i === step);
  }});
  pixels.forEach(el => el.classList.toggle("hot", step === 2 || step === 3));
  document.getElementById("stepCopy").textContent =
    step < 0 ? "Ready · camera presents RGB565" : copies[step];
  const threshold = Number(document.getElementById("threshold").value);
  let value = "—";
  let copy = "Advance to see the edge decision.";
  if (step >= 3) value = "255";
  if (step >= 4) {{
    value = 255 >= threshold ? "255" : "0";
    copy = `255 ≥ ${{threshold}} → edge retained`;
    output.classList.remove("scan");
    void output.offsetWidth;
    output.classList.add("scan");
  }}
  document.getElementById("outputValue").textContent = value;
  document.getElementById("thresholdCopy").textContent = copy;
}}
function next() {{
  step = (step + 1) % 6;
  render();
}}
document.getElementById("next").addEventListener("click", next);
document.getElementById("reset").addEventListener("click", () => {{
  clearInterval(timer); timer = null; step = -1;
  document.getElementById("auto").textContent = "Auto play"; render();
}});
document.getElementById("auto").addEventListener("click", (event) => {{
  if (timer) {{
    clearInterval(timer); timer = null; event.target.textContent = "Auto play";
  }} else {{
    next(); timer = setInterval(next, 950); event.target.textContent = "Pause";
  }}
}});
document.getElementById("threshold").addEventListener("input", event => {{
  document.getElementById("thresholdReadout").textContent = event.target.value; render();
}});
render();
</script>
</body>
</html>
""",
        height=1000,
        scrolling=True,
    )
