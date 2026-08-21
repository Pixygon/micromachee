"""Palette design for micromachee.

A cart says "colour 3" and never learns what colour 3 looks like — the palette
only becomes real in the PLTE chunk of each frame. So a theme can repaint every
game ever written, and the one thing it must not do is break their readability.

The rule: a theme preserves the DEFAULT palette's luminance ORDER and the
relative spacing between slots, mapped onto its own darkest..lightest range.

  slot 0 is always the ground, slot 7 always the lightest, and
  0 < 1 < 2 < 6 < 3 < 5 < 4 < 7 always holds.

Not exact luminance — that was the first attempt and it bleached every theme
white, because no saturated green reaches the default yellow's 0.81. Mapping
proportionally instead lets Game Boy keep a green screen and an amber CRT stay
amber, while a cart that was readable on one is still readable on the other.

Hue per slot is chosen by hand. Brightness is imposed by arithmetic.
"""

DEFAULT = [(0x00,0x00,0x00),(0x1d,0x2b,0x53),(0xff,0x00,0x4d),(0xff,0xa3,0x00),
           (0xff,0xec,0x27),(0x00,0xe4,0x36),(0x29,0xad,0xff),(0xff,0xf1,0xe8)]
ROLES = ["ground","dim","alert","warm","bright","go","cool","light"]

def lin(c):
    c = c/255
    return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def unlin(c):
    c = max(0.0, min(1.0, c))
    return round(255*(12.92*c if c <= 0.0031308 else 1.055*c**(1/2.4)-0.055))
def lum_lin(r,g,b): return 0.2126*r + 0.7152*g + 0.0722*b
def lum(rgb): return lum_lin(*[lin(v) for v in rgb])
def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)))
    return (lb+0.05)/(la+0.05)

BASE = [lum(c) for c in DEFAULT]
BMIN, BMAX = min(BASE), max(BASE)
RANK = sorted(range(8), key=lambda i: BASE[i])   # 0 < 1 < 2 < 6 < 3 < 5 < 4 < 7

# How far to even out the spacing. The default palette bunches its dark end
# (navy sits at 3% of the range), which is fine across a 19:1 spread but makes
# two slots indistinguishable on a theme with a narrow one. Blending the
# default's proportions with even spacing keeps the order — both curves are
# monotone, so any blend of them is — while pulling the crowded end apart.
EVEN = 0.45

def ramp_targets(lo, hi):
    """Where each slot's luminance goes, for a theme spanning lo..hi."""
    pos = {}
    for k, slot in enumerate(RANK):
        prop = (BASE[slot]-BMIN)/(BMAX-BMIN)
        pos[slot] = (1-EVEN)*prop + EVEN*(k/7)
    return {s: lo + p*(hi-lo) for s, p in pos.items()}

def place(rgb, target):
    """Put this hue at `target` luminance, keeping as much of it as physics allows.

    Scaling in linear light preserves chromaticity exactly, so it is always the
    first move. Only when a hue cannot reach the target at full strength — a
    saturated blue tops out around L=0.07, which is why even the default palette's
    blue is a pale sky one — does it mix toward white, and only by the shortfall.
    Mixing first (the obvious implementation) bleaches every mid slot to beige.
    """
    r,g,b = [lin(v) for v in rgb]
    L = lum_lin(r,g,b)
    if target <= 1e-9: return (0,0,0)
    if L <= 1e-9:      return (unlin(target),)*3
    m = max(r,g,b)
    if target <= L/m:                       # reachable by scaling alone
        f = target/L
        r,g,b = r*f, g*f, b*f
    else:                                   # brightest this hue gets, then white
        r,g,b = r/m, g/m, b/m
        Lmax = lum_lin(r,g,b)
        t = (target-Lmax)/(1.0-Lmax) if Lmax < 1.0 else 0.0
        r,g,b = r+(1-r)*t, g+(1-g)*t, b+(1-b)*t
    return (unlin(r), unlin(g), unlin(b))

def hx(s): return (int(s[1:3],16), int(s[3:5],16), int(s[5:7],16))

# ground and light are the theme's real endpoints; the six between get their
# hue from here and their brightness from the mapping.
THEMES = {
  "micromachee": ("#000000","#fff1e8",
                  ["#000000","#1d2b53","#ff004d","#ffa300","#ffec27","#00e436","#29adff","#fff1e8"]),
  # Wider than a real DMG at both ends: the authentic #0f380f..#9bbc0f spread is
  # only 6:1 and collapses two slots into one. This keeps the screen green.
  "gameboy":     ("#08170a","#c7e34a",
                  ["#08170a","#1e4620","#8bac0f","#306230","#c7e34a","#6b9c2f","#3d6b3d","#c7e34a"]),
  "amber":       ("#1a0d00","#ffcf7a",
                  ["#1a0d00","#4a2600","#ff7b1a","#c86a00","#ffb43c","#e08a10","#8a4f08","#ffcf7a"]),
  "noir":        ("#050505","#ffffff",
                  ["#050505","#3a3a3a","#6e6e6e","#8f8f8f","#c8c8c8","#a8a8a8","#7e7e7e","#ffffff"]),
  "sweet":       ("#1a1226","#fdf6ee",
                  ["#1a1226","#3d2a52","#e5486b","#f08b4c","#ffe08a","#7fd98c","#6aa0e0","#fdf6ee"]),
  "abyss":       ("#04070d","#e6f0f8",
                  ["#04070d","#141f36","#c02f4c","#b8763a","#e8dca6","#5f9e7d","#3f6aa8","#e6f0f8"]),
}

def build(name):
    ground, light, hues = THEMES[name]
    if name == "micromachee":
        return [hx(h) for h in hues]            # the reference: used verbatim
    lo, hi = lum(hx(ground)), lum(hx(light))
    tgt = ramp_targets(lo, hi)
    pal = [place(hx(h), tgt[i]) for i, h in enumerate(hues)]
    pal[0], pal[7] = hx(ground), hx(light)      # endpoints land exactly
    return pal

def check(pal):
    ls = [lum(c) for c in pal]
    bad = []
    if sorted(range(8), key=lambda i: ls[i]) != sorted(range(8), key=lambda i: BASE[i]):
        bad.append(f"luminance order broken: {sorted(range(8), key=lambda i: ls[i])}")
    # Text on ground is the case every cart depends on.
    if contrast(pal[7], pal[0]) < 7.0:
        bad.append(f"light on ground is only {contrast(pal[7],pal[0]):.1f}:1")
    # Adjacent ranks must stay apart or two slots read as one colour.
    rank = sorted(range(8), key=lambda i: ls[i])
    for a, b in zip(rank, rank[1:]):
        if ls[b]-ls[a] < 0.012:
            bad.append(f"slots {a}/{b} too close ({ls[a]:.3f}/{ls[b]:.3f})")
    return bad

PALETTES = {n: build(n) for n in THEMES}




# ── export ──────────────────────────────────────────────────────────────────

def hexs(c): return "#%02x%02x%02x" % c
def mix(a, b, t): return tuple(unlin(lin(a[i])*(1-t) + lin(b[i])*t) for i in range(3))
def scale(c, f): return tuple(unlin(lin(v)*f) for v in c)

def export(path="palettes.json"):
    import json, pathlib
    rank = sorted(range(8), key=lambda i: BASE[i])
    out = {
      "note": "Generated by themes/build.py. Slot hues are chosen by hand; luminance "
              "is imposed so every theme preserves the default's luminance rank. "
              "See themes/README.md.",
      "rank": rank,
      "roles": ROLES,
      "themes": {},
    }
    for name, pal in PALETTES.items():
        bad = check(pal)
        if bad:
            raise SystemExit(f"{name} is not a legal theme: " + "; ".join(bad))
        ground, light = pal[0], pal[7]
        out["themes"][name] = {
          "palette": [hexs(c) for c in pal],
          # Derived, never picked separately — see themes/README.md.
          "shell": {
            "body":   hexs(scale(ground, 0.45)),
            "bezel":  hexs(ground),
            "text":   hexs(light),
            "dim":    hexs(mix(ground, light, 0.45)),
            "accent": hexs(pal[2]),
          },
        }
    pathlib.Path(path).write_text(json.dumps(out, indent=2) + "\n")
    return out


if __name__ == "__main__":
    import os
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    for n, pal in PALETTES.items():
        bad = check(pal)
        print(f"{n:12s} {'ok' if not bad else 'FAIL'}  light-on-ground {contrast(pal[7],pal[0]):5.1f}:1")
        print("             " + " ".join("#%02x%02x%02x" % c for c in pal))
        for b in bad:
            print("             ! " + b)
    export()
    print("\nwrote palettes.json")
