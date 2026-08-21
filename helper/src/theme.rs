//! Colour modes.
//!
//! A theme is the eight-colour palette **and** the shell around the screen,
//! swapped together. They are one thing because the alternative is a console
//! whose body and screen slowly stop matching.
//!
//! This costs nothing at runtime. A cart says "colour 3" and never learns what
//! colour 3 looks like — the palette only becomes real in the PLTE chunk of a
//! PNG, once per frame. So a theme is a different set of PLTE bytes, and no
//! cart can tell which one it is running under.
//!
//! ## The rule that makes it safe
//!
//! **A theme must preserve the luminance rank of the eight slots**: sorted dark
//! to light they are always `0, 1, 2, 6, 3, 5, 4, 7`. Not the distances — the
//! order. Every game's readability is built on those relative contrasts, and a
//! cart author never chose the colours, so if a theme could reorder them it
//! could make every existing game unreadable and nobody could do anything about
//! it. Preserve the order and anything readable in one theme is readable in all
//! of them, including monochrome ones. It is checked by a test, not by eye.
//!
//! The palettes themselves are generated — see `palettes.rs` and
//! `themes/README.md`.

use crate::palettes;

pub type Palette = [(u8, u8, u8); 8];

#[derive(Debug, Clone)]
pub struct Theme {
    pub id: String,
    pub palette: Palette,
    /// The console body around the screen. Derived from the palette rather than
    /// chosen beside it, so a new palette gets a matching shell for free and the
    /// two cannot drift apart.
    pub shell: Shell,
}

#[derive(Debug, Clone)]
pub struct Shell {
    pub body: String,
    pub bezel: String,
    pub text: String,
    pub dim: String,
    pub accent: String,
}

/// The luminance order every theme has to keep.
pub fn rank() -> Vec<usize> {
    palettes::rank()
}

pub fn ids() -> Vec<String> {
    palettes::THEMES.iter().map(|t| t.0.to_string()).collect()
}

pub fn get(id: &str) -> Option<Theme> {
    let palette = palettes::build(id)?;
    let sh = palettes::shell(&palette);
    let pick = |key: &str| {
        sh.iter()
            .find(|(k, _)| *k == key)
            .map(|(_, v)| v.clone())
            .unwrap_or_default()
    };
    Some(Theme {
        id: id.to_string(),
        palette,
        shell: Shell {
            body: pick("body"),
            bezel: pick("bezel"),
            text: pick("text"),
            dim: pick("dim"),
            accent: pick("accent"),
        },
    })
}

pub const DEFAULT_ID: &str = "micromachee";

/// The theme in force, in order of who gets the last word: an explicit
/// environment variable, then whatever was chosen and saved, then the default.
pub fn active(saved: Option<&str>) -> Theme {
    if let Ok(id) = std::env::var("MICROMACHEE_THEME") {
        if let Some(t) = get(&id) {
            return t;
        }
    }
    if let Some(t) = saved.and_then(get) {
        return t;
    }
    get(DEFAULT_ID).unwrap_or(Theme {
        id: DEFAULT_ID.into(),
        palette: crate::console::DEFAULT_PALETTE,
        shell: Shell {
            body: "#000000".into(),
            bezel: "#000000".into(),
            text: "#fff1e8".into(),
            dim: "#b3a9a2".into(),
            accent: "#ff004d".into(),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn linear(c: u8) -> f64 {
        let c = c as f64 / 255.0;
        if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
    }
    fn luminance((r, g, b): (u8, u8, u8)) -> f64 {
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    #[test]
    fn there_are_themes_and_the_default_is_one_of_them() {
        let ids = ids();
        assert!(ids.len() >= 2, "got {ids:?}");
        assert!(ids.iter().any(|i| i == DEFAULT_ID));
    }

    #[test]
    fn every_theme_preserves_the_default_luminance_rank() {
        // The load-bearing rule. A theme that reorders the slots makes every
        // existing cart unreadable, and no cart author can do anything about it
        // because they never chose the colours. Asserted against the rank in
        // the data rather than a hardcoded list, so the two cannot disagree.
        let want = rank();
        assert_eq!(want.len(), 8);
        for id in ids() {
            let t = get(&id).unwrap_or_else(|| panic!("{id} did not parse"));
            let mut order: Vec<usize> = (0..8).collect();
            order.sort_by(|&a, &b| {
                luminance(t.palette[a]).partial_cmp(&luminance(t.palette[b])).unwrap()
            });
            assert_eq!(order, want, "theme {id} reorders the palette");
        }
    }

    #[test]
    fn light_on_ground_stays_legible_in_every_theme() {
        // Slot 7 on slot 0 is what almost every game prints its score in.
        for id in ids() {
            let t = get(&id).unwrap();
            let (hi, lo) = (luminance(t.palette[7]), luminance(t.palette[0]));
            let contrast = (hi + 0.05) / (lo + 0.05);
            assert!(contrast >= 7.0, "theme {id} has only {contrast:.1}:1 for text on ground");
        }
    }

    #[test]
    fn no_two_slots_collapse_into_each_other() {
        // Equal luminance is a rank that happens to sort correctly today and
        // could sort either way tomorrow — and two slots that look identical
        // are one slot as far as a player is concerned.
        let order = rank();
        for id in ids() {
            let t = get(&id).unwrap();
            for w in order.windows(2) {
                let d = luminance(t.palette[w[1]]) - luminance(t.palette[w[0]]);
                assert!(d > 0.005, "theme {id}: slots {} and {} are the same shade", w[0], w[1]);
            }
        }
    }

    #[test]
    fn every_theme_has_a_full_shell() {
        for id in ids() {
            let t = get(&id).unwrap();
            for (what, v) in [
                ("body", &t.shell.body), ("bezel", &t.shell.bezel), ("text", &t.shell.text),
                ("dim", &t.shell.dim), ("accent", &t.shell.accent),
            ] {
                // QML puts these straight into a colour property, so the
                // format matters as much as the value.
                assert!(
                    v.len() == 7
                        && v.starts_with('#')
                        && v[1..].chars().all(|c| c.is_ascii_hexdigit()),
                    "theme {id} has a bad {what}: {v:?}"
                );
            }
        }
    }

    #[test]
    fn an_unknown_theme_falls_back_rather_than_failing() {
        // A saved theme that a later version removed must not stop the console
        // from drawing.
        assert_eq!(active(Some("no-such-theme")).id, DEFAULT_ID);
        assert_eq!(active(None).id, DEFAULT_ID);
    }
}
