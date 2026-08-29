//! Where the colour modes come from.
//!
//! Hue per slot is chosen by hand. **Brightness is imposed by arithmetic**, so
//! the rule that keeps every cart readable — see `theme.rs` — holds by
//! construction rather than by eyeballing a render.
//!
//! Each theme names its own darkest and lightest colour. The six slots between
//! take the default palette's luminance *proportions*, blended toward even
//! spacing, mapped onto that range. Both curves rise, so any blend of them
//! rises: the luminance order cannot break no matter what hues are picked.
//!
//! Two things here are worth not re-deriving, because both were got wrong once:
//!
//!   * **Do not hold luminance exactly equal to the default.** It passes every
//!     check and bleaches every theme — no saturated green reaches the default
//!     yellow's 0.81, so Game Boy's slot 4 comes out near-white.
//!   * **Do not brighten by mixing toward white.** Scaling in linear light
//!     preserves the hue exactly and must be tried first; white is only for the
//!     shortfall a hue physically cannot cover. Mixing first turns an amber CRT
//!     into wet sand.
//!
//! `themes/palettes.json` is generated from this and committed, because the
//! binary bakes it in and a console that cannot draw until it finds a file is a
//! console with a way to be broken. A test regenerates and compares, so the two
//! cannot drift; see `themes/README.md` for how to add one.

use crate::console::DEFAULT_PALETTE;

type Rgb = (u8, u8, u8);

/// How far to even out the spacing. The default bunches its dark end — navy
/// sits at 3% of the range — which is fine across a 19:1 spread and collapses
/// two slots on a narrow one.
const EVEN: f64 = 0.45;

#[cfg(test)]
pub const ROLES: [&str; 8] =
    ["ground", "dim", "alert", "warm", "bright", "go", "cool", "light"];

/// id, ground, light, and the eight hues.
pub const THEMES: [(&str, &str, &str, [&str; 8]); 6] = [
    ("micromachee", "#000000", "#fff1e8",
     ["#000000","#1d2b53","#ff004d","#ffa300","#ffec27","#00e436","#29adff","#fff1e8"]),
    // Wider than a real DMG at both ends: the authentic #0f380f..#9bbc0f spread
    // is only 6:1 and collapses two slots into one. This keeps the screen green.
    ("gameboy", "#08170a", "#c7e34a",
     ["#08170a","#1e4620","#8bac0f","#306230","#c7e34a","#6b9c2f","#3d6b3d","#c7e34a"]),
    ("amber", "#1a0d00", "#ffcf7a",
     ["#1a0d00","#4a2600","#ff7b1a","#c86a00","#ffb43c","#e08a10","#8a4f08","#ffcf7a"]),
    ("noir", "#050505", "#ffffff",
     ["#050505","#3a3a3a","#6e6e6e","#8f8f8f","#c8c8c8","#a8a8a8","#7e7e7e","#ffffff"]),
    ("sweet", "#1a1226", "#fdf6ee",
     ["#1a1226","#3d2a52","#e5486b","#f08b4c","#ffe08a","#7fd98c","#6aa0e0","#fdf6ee"]),
    ("abyss", "#04070d", "#e6f0f8",
     ["#04070d","#141f36","#c02f4c","#b8763a","#e8dca6","#5f9e7d","#3f6aa8","#e6f0f8"]),
];

/// How a theme's screen is PRESENTED.
///
/// A palette says what colour slot 3 is. This says what the *glass* does to it:
/// the scanline gaps of a CRT, the glow of a phosphor, the RGB fringing of a
/// shadow mask, the flat cell grid of an LCD. It changes no pixel a cart drew —
/// the framebuffer is identical either way, which is why the pixel-parity check
/// still passes — it only changes how those pixels are painted onto the display.
///
/// Every field is 0..1 and 0 means "not this screen". A theme imitating real
/// hardware turns on the things that hardware actually did and nothing else:
/// a Game Boy has no scanlines and no bloom, an amber phosphor tube has no
/// colour fringing because it has only one phosphor.
#[derive(Clone, Copy)]
pub struct Fx {
    /// dark gaps between raster lines
    pub scanline: f64,
    /// light bleeding out of bright pixels
    pub bloom: f64,
    /// red/blue fringing, in console pixels of separation
    pub aberration: f64,
    /// moving grain
    pub noise: f64,
    /// the tube going dark toward the corners
    pub vignette: f64,
    /// LCD cell structure: gaps on BOTH axes rather than lines
    pub grid: f64,
    /// how much of the last frame lingers — phosphor glow, or LCD smear
    pub persist: f64,
}

const fn fx(scanline: f64, bloom: f64, aberration: f64, noise: f64, vignette: f64, grid: f64, persist: f64) -> Fx {
    Fx { scanline, bloom, aberration, noise, vignette, grid, persist }
}

/// One row per theme, in the same order as `THEMES`. A test fails if the two
/// lists stop agreeing, because a theme with no screen described for it would
/// silently fall back to plain flat pixels.
pub const FX: [(&str, Fx); 6] = [
    //                     scan  bloom  abrr  noise  vign  grid  persist
    // The arcade cabinet it is named for: a bright RGB tube, mask fringing at
    // the edges of saturated colour, and just enough grain to not look printed.
    ("micromachee", fx(0.30, 0.34, 0.55, 0.030, 0.22, 0.00, 0.06)),
    // A DMG is a reflective LCD: no raster, no glow, a visible cell grid, and
    // the famous smear when anything moves fast.
    ("gameboy",     fx(0.00, 0.00, 0.00, 0.000, 0.14, 0.55, 0.34)),
    // One amber phosphor. It has no colours to fringe, and it GLOWS — long
    // persistence was the whole complaint about these monitors.
    ("amber",       fx(0.32, 0.55, 0.00, 0.045, 0.30, 0.00, 0.30)),
    // A small black-and-white set with the contrast up: hard raster, real
    // static, and the corners falling away.
    ("noir",        fx(0.40, 0.22, 0.12, 0.110, 0.34, 0.00, 0.10)),
    // Not hardware — a soft modern panel. Bloom and a little fringing, no
    // raster at all, because nothing it imitates ever had one.
    ("sweet",       fx(0.00, 0.44, 0.22, 0.015, 0.14, 0.00, 0.08)),
    // Deep and underlit: the glow of a screen in a dark room, corners gone.
    ("abyss",       fx(0.16, 0.32, 0.20, 0.040, 0.44, 0.00, 0.14)),
];

/// The screen a theme is shown on, or a flat one if it never named its own.
pub fn fx_for(id: &str) -> Fx {
    FX.iter().find(|(n, _)| *n == id).map(|(_, f)| *f).unwrap_or(fx(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
}

fn linear(c: u8) -> f64 {
    let c = c as f64 / 255.0;
    if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
}

fn encode(c: f64) -> u8 {
    let c = c.clamp(0.0, 1.0);
    let v = if c <= 0.003_130_8 { 12.92 * c } else { 1.055 * c.powf(1.0 / 2.4) - 0.055 };
    (255.0 * v).round() as u8
}

fn lum_lin(r: f64, g: f64, b: f64) -> f64 {
    0.2126 * r + 0.7152 * g + 0.0722 * b
}

pub fn luminance((r, g, b): Rgb) -> f64 {
    lum_lin(linear(r), linear(g), linear(b))
}

pub fn hex(s: &str) -> Rgb {
    let s = s.trim_start_matches('#');
    (
        u8::from_str_radix(&s[0..2], 16).unwrap_or(0),
        u8::from_str_radix(&s[2..4], 16).unwrap_or(0),
        u8::from_str_radix(&s[4..6], 16).unwrap_or(0),
    )
}

pub fn to_hex((r, g, b): Rgb) -> String {
    format!("#{r:02x}{g:02x}{b:02x}")
}

/// Put this hue at `target` luminance, keeping as much of it as physics allows.
fn place(rgb: Rgb, target: f64) -> Rgb {
    let (mut r, mut g, mut b) = (linear(rgb.0), linear(rgb.1), linear(rgb.2));
    let l = lum_lin(r, g, b);
    if target <= 1e-9 {
        return (0, 0, 0);
    }
    if l <= 1e-9 {
        let v = encode(target);
        return (v, v, v);
    }
    let m = r.max(g).max(b);
    if target <= l / m {
        // Reachable by scaling alone, which preserves chromaticity exactly.
        let f = target / l;
        r *= f;
        g *= f;
        b *= f;
    } else {
        // As bright as this hue gets, then toward white for the shortfall.
        r /= m;
        g /= m;
        b /= m;
        let l_max = lum_lin(r, g, b);
        let t = if l_max < 1.0 { (target - l_max) / (1.0 - l_max) } else { 0.0 };
        r += (1.0 - r) * t;
        g += (1.0 - g) * t;
        b += (1.0 - b) * t;
    }
    (encode(r), encode(g), encode(b))
}

fn base() -> [f64; 8] {
    let mut out = [0.0; 8];
    for i in 0..8 {
        out[i] = luminance(DEFAULT_PALETTE[i]);
    }
    out
}

/// Slots ordered dark to light: `0, 1, 2, 6, 3, 5, 4, 7`.
pub fn rank() -> Vec<usize> {
    let b = base();
    let mut order: Vec<usize> = (0..8).collect();
    order.sort_by(|&x, &y| b[x].partial_cmp(&b[y]).unwrap());
    order
}

pub fn build(id: &str) -> Option<[Rgb; 8]> {
    let (_, ground, light, hues) = THEMES.iter().find(|t| t.0 == id)?;
    let g = hex(ground);
    let l = hex(light);
    if id == "micromachee" {
        // The reference the others are measured against, used verbatim.
        let mut p = [(0u8, 0u8, 0u8); 8];
        for i in 0..8 {
            p[i] = hex(hues[i]);
        }
        return Some(p);
    }
    let (lo, hi) = (luminance(g), luminance(l));
    let b = base();
    let (bmin, bmax) = (
        b.iter().cloned().fold(f64::MAX, f64::min),
        b.iter().cloned().fold(f64::MIN, f64::max),
    );
    let order = rank();
    let mut target = [0.0f64; 8];
    for (k, &slot) in order.iter().enumerate() {
        let prop = (b[slot] - bmin) / (bmax - bmin);
        let pos = (1.0 - EVEN) * prop + EVEN * (k as f64 / 7.0);
        target[slot] = lo + pos * (hi - lo);
    }
    let mut p = [(0u8, 0u8, 0u8); 8];
    for i in 0..8 {
        p[i] = place(hex(hues[i]), target[i]);
    }
    p[0] = g;
    p[7] = l;
    Some(p)
}

fn scale(c: Rgb, f: f64) -> Rgb {
    (
        encode(linear(c.0) * f),
        encode(linear(c.1) * f),
        encode(linear(c.2) * f),
    )
}

fn mix(a: Rgb, b: Rgb, t: f64) -> Rgb {
    (
        encode(linear(a.0) * (1.0 - t) + linear(b.0) * t),
        encode(linear(a.1) * (1.0 - t) + linear(b.1) * t),
        encode(linear(a.2) * (1.0 - t) + linear(b.2) * t),
    )
}

/// The shell is derived from the palette, never picked alongside it, so a theme
/// cannot drift out of sync with its own chrome and a new palette gets a
/// matching console body for free.
pub fn shell(p: &[Rgb; 8]) -> [(&'static str, String); 5] {
    [
        ("body", to_hex(scale(p[0], 0.45))),
        ("bezel", to_hex(p[0])),
        ("text", to_hex(p[7])),
        ("dim", to_hex(mix(p[0], p[7], 0.45))),
        ("accent", to_hex(p[2])),
    ]
}

/// The committed `themes/palettes.json`, regenerated. The binary builds its
/// palettes directly; this exists so the exported artifact cannot drift.
#[cfg(test)]
pub fn generate() -> String {
    let mut s = String::from("{\n");
    s.push_str("  \"note\": \"Generated by helper/src/palettes.rs. Slot hues are chosen by hand; luminance is imposed so every theme preserves the default's luminance rank. See themes/README.md.\",\n");
    s.push_str(&format!(
        "  \"rank\": [{}],\n",
        rank().iter().map(|n| n.to_string()).collect::<Vec<_>>().join(", ")
    ));
    s.push_str(&format!(
        "  \"roles\": [{}],\n",
        ROLES.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(", ")
    ));
    s.push_str("  \"themes\": {\n");
    for (n, (id, _, _, _)) in THEMES.iter().enumerate() {
        let p = build(id).expect("every listed theme builds");
        s.push_str(&format!("    \"{id}\": {{\n      \"palette\": ["));
        s.push_str(
            &p.iter().map(|c| format!("\"{}\"", to_hex(*c))).collect::<Vec<_>>().join(", "),
        );
        s.push_str("],\n      \"shell\": {");
        s.push_str(
            &shell(&p)
                .iter()
                .map(|(k, v)| format!("\"{k}\": \"{v}\""))
                .collect::<Vec<_>>()
                .join(", "),
        );
        s.push_str("},\n      \"fx\": {");
        let f = fx_for(id);
        s.push_str(&format!(
            "\"scanline\": {:.3}, \"bloom\": {:.3}, \"aberration\": {:.3}, \"noise\": {:.3}, \"vignette\": {:.3}, \"grid\": {:.3}, \"persist\": {:.3}",
            f.scanline, f.bloom, f.aberration, f.noise, f.vignette, f.grid, f.persist
        ));
        s.push_str("}\n    }");
        s.push_str(if n + 1 == THEMES.len() { "\n" } else { ",\n" });
    }
    s.push_str("  }\n}\n");
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    const COMMITTED: &str = include_str!("../../themes/palettes.json");

    #[test]
    fn the_committed_palettes_are_what_this_generates() {
        // Regenerate with:  MICROMACHEE_WRITE_PALETTES=1 cargo test -p omarchy-micromachee
        if std::env::var("MICROMACHEE_WRITE_PALETTES").is_ok() {
            let root = concat!(env!("CARGO_MANIFEST_DIR"), "/..");
            std::fs::write(format!("{root}/themes/palettes.json"), generate())
                .expect("could not write palettes.json");
            std::fs::create_dir_all(format!("{root}/web")).ok();
            std::fs::write(format!("{root}/web/console-data.js"), generate_js())
                .expect("could not write web/console-data.js");
            return;
        }
        assert_eq!(
            generate(),
            COMMITTED,
            "themes/palettes.json is stale — regenerate it (see the comment above)"
        );
    }

    #[test]
    fn the_web_players_font_and_palettes_are_what_this_generates() {
        const COMMITTED: &str = include_str!("../../web/console-data.js");
        assert_eq!(
            generate_js(),
            COMMITTED,
            "web/console-data.js is stale — regenerate it (see the comment above)"
        );
    }

    #[test]
    fn placing_a_hue_hits_the_luminance_it_was_asked_for() {
        for hue in ["#ff004d", "#00e436", "#29adff", "#8bac0f"] {
            for target in [0.05, 0.2, 0.5, 0.8] {
                let got = luminance(place(hex(hue), target));
                assert!((got - target).abs() < 0.02, "{hue} at {target} landed on {got}");
            }
        }
    }

    #[test]
    fn brightening_keeps_the_hue_rather_than_washing_it_out() {
        // The bug this exists for: mixing toward white first turned amber's
        // mid slots to beige. A brightened orange must still be orange.
        let (r, g, b) = place(hex("#c86a00"), 0.45);
        assert!(r > g && g > b, "#c86a00 brightened to {r},{g},{b}");
        assert!(r as i32 - b as i32 > 90, "lost its saturation: {r},{g},{b}");
    }

    #[test]
    fn every_theme_describes_the_screen_it_is_shown_on() {
        // A theme with no FX row would quietly render as flat pixels while
        // every other theme looked like hardware — the kind of gap nobody sees
        // until they swap to that one theme.
        assert_eq!(FX.len(), THEMES.len(), "FX and THEMES have drifted apart");
        for ((fid, _), (tid, _, _, _)) in FX.iter().zip(THEMES.iter()) {
            assert_eq!(fid, tid, "FX is not in the same order as THEMES");
        }
        for (id, f) in FX.iter() {
            for (what, v) in [("scanline", f.scanline), ("bloom", f.bloom), ("aberration", f.aberration),
                              ("noise", f.noise), ("vignette", f.vignette), ("grid", f.grid), ("persist", f.persist)] {
                assert!((0.0..=1.0).contains(&v), "{id}: {what} is {v}, outside 0..1");
            }
        }
    }

    #[test]
    fn every_generated_theme_keeps_the_rank() {
        let want = rank();
        for (id, _, _, _) in THEMES.iter() {
            let p = build(id).unwrap();
            let mut order: Vec<usize> = (0..8).collect();
            order.sort_by(|&a, &b| luminance(p[a]).partial_cmp(&luminance(p[b])).unwrap());
            assert_eq!(order, want, "{id} reorders the palette");
        }
    }
}


// ── the web player's copy ───────────────────────────────────────────────────

/// The font and the palettes, as JavaScript.
///
/// The page at pixygon.io draws with its own renderer, so it needs the same
/// font table and the same eight colours. Generating them from here rather than
/// copying them by hand is the only thing that keeps the two from drifting —
/// and a test regenerates and compares, so drift fails the build.
#[cfg(test)]
pub fn generate_js() -> String {
    use crate::console;
    let mut s = String::from(
        "// Generated by helper/src/palettes.rs — do not edit.\n\
         // Regenerate: MICROMACHEE_WRITE_PALETTES=1 cargo test --manifest-path helper/Cargo.toml\n\n",
    );
    // The page must ask for the same shelf this build publishes. Generating the
    // url here means the two cannot drift when the version moves.
    s.push_str(&format!(
        "export const VERSION = \"{}\";\nexport const CATALOG =\n  \"{}\";\n\n",
        env!("CARGO_PKG_VERSION"),
        crate::shelf::catalog_url()
    ));
    s.push_str("export const W = 128;\nexport const H = 128;\n");
    s.push_str("export const CHAR_WIDTH = 4;\nexport const LINE_HEIGHT = 6;\n\n");

    s.push_str("// slot -> five rows of three bits, most significant bit leftmost\nexport const FONT = {\n");
    for (ch, rows) in console::font_table() {
        let key = match ch {
            '\\' => "\\\\".to_string(),
            '"' => "\\\"".to_string(),
            c => c.to_string(),
        };
        s.push_str(&format!(
            "  \"{key}\": [{}],\n",
            rows.iter().map(|r| r.to_string()).collect::<Vec<_>>().join(",")
        ));
    }
    s.push_str("};\n\n");

    s.push_str("// dark to light; every theme keeps this order\nexport const RANK = [");
    s.push_str(&rank().iter().map(|n| n.to_string()).collect::<Vec<_>>().join(", "));
    s.push_str("];\n\nexport const THEMES = {\n");
    for (id, _, _, _) in THEMES.iter() {
        let p = build(id).expect("every listed theme builds");
        s.push_str(&format!(
            "  \"{id}\": [{}],\n",
            p.iter().map(|c| format!("\"{}\"", to_hex(*c))).collect::<Vec<_>>().join(", ")
        ));
    }
    s.push_str("};\n\n");

    // How each theme is PRESENTED. Generated here beside the palettes for the
    // same reason they are: the web player draws the screen a second time, and
    // a hand-copied table is a table that drifts.
    s.push_str("// the screen each theme imitates — display effects, never pixels\nexport const THEME_FX = {\n");
    for (id, _, _, _) in THEMES.iter() {
        let f = fx_for(id);
        s.push_str(&format!(
            "  \"{id}\": {{ scanline: {:.3}, bloom: {:.3}, aberration: {:.3}, noise: {:.3}, vignette: {:.3}, grid: {:.3}, persist: {:.3} }},\n",
            f.scanline, f.bloom, f.aberration, f.noise, f.vignette, f.grid, f.persist
        ));
    }
    s.push_str("};\n");
    s
}
