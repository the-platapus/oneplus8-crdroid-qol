#!/usr/bin/env python3
"""Draws docs/eq-curve.svg from the Graphic EQ stored in files/jamesdsp/Oneplus_8_speakers.tar.

Reads the preset itself, so the chart always shows exactly what JamesDSP loads.
Points are joined with straight lines on a log-frequency axis. Standard library only.
  python3 docs/eq-curve.py
"""
import math
import pathlib
import tarfile
import xml.dom.minidom

ROOT = pathlib.Path(__file__).resolve().parent.parent
PRESET = ROOT / "files/jamesdsp/Oneplus_8_speakers.tar"
OUT = ROOT / "docs/eq-curve.svg"

W, H = 820, 330
L, R, T, B = 58, 22, 22, 46          # plot margins
F0, F1 = 20, 20000                   # Hz
D0, D1 = -9, 3                       # dB


def nodes():
    with tarfile.open(PRESET) as t:
        doc = xml.dom.minidom.parseString(t.extractfile("dsp_graphiceq.xml").read())
    for e in doc.getElementsByTagName("string"):
        if e.getAttribute("name") == "geq_nodes":
            text = e.firstChild.data
    assert text.startswith("GraphicEQ:")
    pts = []
    for part in text[len("GraphicEQ:"):].split(";"):
        if part.strip():
            f, g = part.split()
            pts.append((float(f), float(g)))
    return pts


def x(f):
    return L + (W - L - R) * (math.log10(f) - math.log10(F0)) / (math.log10(F1) - math.log10(F0))


def y(db):
    return T + (H - T - B) * (D1 - db) / (D1 - D0)


def num(v):
    s = f"{v:g}"
    return s.replace("-", "−") if v < 0 else (f"+{s}" if v > 0 else s)


def hz(f):
    return f"{f / 1000:g}k" if f >= 1000 else f"{f:g}"


def main():
    pts = nodes()
    o = []
    o.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" '
             f'aria-labelledby="t d">')
    o.append('<title id="t">Graphic EQ of the Oneplus_8_speakers JamesDSP preset</title>')
    o.append('<desc id="d">' + ", ".join(f"{hz(f)} Hz {num(g)} dB" for f, g in pts) + "</desc>")
    o.append("""<style>
  .ax{stroke:#d0d7de;stroke-width:1}
  .zero{stroke:#8c959f;stroke-width:1.2}
  .lbl{fill:#59636e;font:12px -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
  .unit{fill:#59636e;font:600 12px -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
  .area{fill:#0969da;fill-opacity:.12}
  .line{fill:none;stroke:#0969da;stroke-width:2.4;stroke-linejoin:round}
  .pt{fill:#0969da;stroke:#ffffff;stroke-width:1.5}
  @media (prefers-color-scheme: dark){
    .ax{stroke:#30363d}.zero{stroke:#6e7681}.lbl,.unit{fill:#9198a1}
    .area{fill:#4493f8;fill-opacity:.16}.line{stroke:#4493f8}.pt{fill:#4493f8;stroke:#0d1117}
  }
</style>""")
    # grid: dB every 3, Hz decades + 2/5 steps
    for db in range(D0, D1 + 1, 3):
        cls = "zero" if db == 0 else "ax"
        o.append(f'<line class="{cls}" x1="{L}" x2="{W - R}" y1="{y(db):.1f}" y2="{y(db):.1f}"/>')
        o.append(f'<text class="lbl" x="{L - 8}" y="{y(db) + 4:.1f}" text-anchor="end">{num(db)}</text>')
    for f in (20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000):
        o.append(f'<line class="ax" x1="{x(f):.1f}" x2="{x(f):.1f}" y1="{T}" y2="{H - B}"/>')
        o.append(f'<text class="lbl" x="{x(f):.1f}" y="{H - B + 18}" text-anchor="middle">{hz(f)}</text>')
    o.append(f'<text class="unit" x="{W - R}" y="{H - 8}" text-anchor="end">Hz</text>')
    o.append(f'<text class="unit" x="14" y="{T + 4}">dB</text>')
    # cut/boost area against 0 dB, the curve, the points
    path = " ".join(f"{x(f):.1f},{y(g):.1f}" for f, g in pts)
    o.append(f'<polygon class="area" points="{x(pts[0][0]):.1f},{y(0):.1f} {path} {x(pts[-1][0]):.1f},{y(0):.1f}"/>')
    o.append(f'<polyline class="line" points="{path}"/>')
    for f, g in pts:
        o.append(f'<circle class="pt" cx="{x(f):.1f}" cy="{y(g):.1f}" r="3.6"><title>{hz(f)} Hz: {num(g)} dB</title></circle>')
    o.append("</svg>")
    OUT.write_text("\n".join(o) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(pts)} points")


if __name__ == "__main__":
    main()
