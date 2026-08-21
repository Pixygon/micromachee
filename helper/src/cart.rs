//! A cartridge is one Lua file. That is the whole format.
//!
//! No sprite sheet, no map, no binary container, no editor — because the point
//! of this console is that anybody, including an agent with nothing but a text
//! editor, can write a whole game in one shot and have it be a legal cart.
//!
//! ```lua
//! -- title: Snake
//! -- author: you
//! -- about: eat, grow, do not bite yourself
//!
//! function _init() ... end
//! function _update() ... end
//! function _draw() ... end
//! ```
//!
//! **Only three things are required**: it fits in 24K, it parses as Lua, and it
//! defines `_draw`. Everything else — title, author, a format tag — is an
//! optional comment. That is a stance rather than laxity: every mandatory line
//! in a header is one more thing to get wrong on a first attempt, and a console
//! whose barrier to entry is "you forgot line one" is one nobody writes a
//! second game for.
//!
//! What a loose format usually costs is a loader full of special cases. Not
//! here, because there is nothing to special-case: the file is Lua, and Lua's
//! own parser is the arbiter.

use std::path::Path;

use crate::console;

/// Hard ceiling on a cart, in bytes.
///
/// A design tool, not a storage worry. 24 KB of Lua is an enormous amount of
/// game — a few thousand lines — and the cap is what keeps a cart the kind of
/// thing somebody writes in an afternoon and reads in one sitting. Checked on
/// load as well as on publish, so an oversized cart cannot arrive by any route.
pub const MAX_CART_BYTES: usize = 24 * 1024;

#[derive(Debug, Clone)]
pub struct Cart {
    pub id: String,
    pub title: String,
    pub author: String,
    pub about: String,
    pub code: String,
    pub bytes: usize,
}

impl Cart {
    pub fn parse(id: &str, source: &str) -> Result<Cart, String> {
        let bytes = source.len();
        if bytes > MAX_CART_BYTES {
            return Err(format!(
                "this cart is {bytes} bytes and a cart has to fit in {MAX_CART_BYTES} — {} too many",
                bytes - MAX_CART_BYTES
            ));
        }
        if source.trim().is_empty() {
            return Err("this cart is empty".into());
        }

        // Metadata is read from the leading comment block and stops at the
        // first line of code, so a `-- title:` written halfway down a file
        // cannot quietly rename someone else's game.
        let meta = |key: &str| -> Option<String> {
            for line in source.lines() {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                let Some(rest) = line.strip_prefix("--") else {
                    break; // code begins; the header is over
                };
                if let Some(v) = rest.trim().strip_prefix(&format!("{key}:")) {
                    let v = v.trim();
                    if !v.is_empty() {
                        return Some(v.chars().take(48).collect());
                    }
                }
            }
            None
        };

        // The one structural requirement. Without `_draw` there is nothing to
        // look at, and the failure would otherwise be a black screen with no
        // explanation — the least debuggable outcome a console can produce.
        if !source.contains("_draw") {
            return Err("this cart has no _draw() — nothing would ever appear on screen".into());
        }

        Ok(Cart {
            id: id.to_string(),
            title: meta("title").unwrap_or_else(|| id.to_string()),
            author: meta("author").unwrap_or_else(|| "anonymous".into()),
            about: meta("about").unwrap_or_default(),
            code: source.to_string(),
            bytes,
        })
    }

    pub fn load(path: &Path) -> Result<Cart, String> {
        let id = path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "cart".into());
        let source =
            std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        Cart::parse(&id, &source)
    }

    /// Things worth telling an author, that are not worth refusing a cart over.
    ///
    /// The menu draws in a 3×5 font with no lower case and a limited set of
    /// symbols, so a title containing anything else appears with a hole in it.
    /// Annoying, visible, and entirely the author's call — which is exactly the
    /// shape of a warning rather than an error.
    pub fn warnings(&self) -> Vec<String> {
        let mut out = Vec::new();
        for (field, value) in [("title", &self.title), ("author", &self.author)] {
            if let Some(bad) = value.chars().find(|&c| !console::can_render(c)) {
                out.push(format!(
                    "the console has no glyph for {bad:?}, so the {field} prints with a gap"
                ));
            }
        }
        // 128 pixels at four per character is 32, and the menu indents a little.
        if self.title.chars().count() > 28 {
            out.push(format!(
                "the title is {} characters; the menu shows about 28",
                self.title.chars().count()
            ));
        }
        out
    }
}

/// A starting cart that already plays, because the fastest way to learn a
/// console is to change something that already moves.
pub fn scaffold(title: &str) -> String {
    format!(
        r#"-- title: {title}
-- author: you
-- about: a starting point

-- 128x128, eight colours:
--   0 black  1 navy  2 red   3 orange
--   4 yellow 5 green 6 blue  7 white
-- buttons: 0 left  1 right  2 up  3 down  4 O(z)  5 X(x)

function _init()
  x, y = 64, 64
  n = 0
end

function _update()
  if btn(0) then x = x - 2 end
  if btn(1) then x = x + 2 end
  if btn(2) then y = y - 2 end
  if btn(3) then y = y + 2 end
  x = mid(4, x, 123)
  y = mid(4, y, 123)
  if btnp(4) then n = n + 1 score(n) end
end

function _draw()
  cls(1)
  circ(x, y, 4, 4)
  print("{upper}", 4, 4, 7)
  print("MOVE. Z SCORES. N=" .. n, 4, 118, 6)
end
"#,
        title = title,
        upper = title.to_uppercase()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const OK: &str = "-- title: Snake\n-- author: you\nfunction _draw() end\n";

    #[test]
    fn metadata_comes_out_of_the_comments() {
        let c = Cart::parse("snake", OK).unwrap();
        assert_eq!(c.title, "Snake");
        assert_eq!(c.author, "you");
    }

    #[test]
    fn a_cart_that_is_only_code_is_still_a_cart() {
        // The headline requirement: an agent writes a game in one shot and it
        // runs. Metadata is a courtesy, never a gate.
        let c = Cart::parse("thing", "function _draw() cls(2) end").unwrap();
        assert_eq!(c.title, "thing");
        assert_eq!(c.author, "anonymous");
    }

    #[test]
    fn the_header_stops_at_the_first_line_of_code() {
        let src = format!("{OK}\n-- title: Hijacked\n");
        assert_eq!(Cart::parse("snake", &src).unwrap().title, "Snake");
    }

    #[test]
    fn oversized_carts_are_refused_and_say_by_how_much() {
        let big = format!("-- title: Big\nfunction _draw() end\n{}", "-".repeat(MAX_CART_BYTES));
        let err = Cart::parse("big", &big).unwrap_err();
        assert!(err.contains("24576"), "{err}");
        assert!(err.contains("too many"), "an author needs the number: {err}");
    }

    #[test]
    fn the_limit_is_twenty_four_k_and_inclusive() {
        let exact = format!("{OK}{}", "-".repeat(MAX_CART_BYTES - OK.len()));
        assert_eq!(exact.len(), 24 * 1024);
        assert!(Cart::parse("edge", &exact).is_ok(), "a cart exactly at the limit is legal");
    }

    #[test]
    fn a_cart_that_draws_nothing_is_refused() {
        let err = Cart::parse("blank", "function _update() end").unwrap_err();
        assert!(err.contains("_draw"), "{err}");
    }

    #[test]
    fn an_empty_cart_is_refused() {
        assert!(Cart::parse("nothing", "   \n\n").is_err());
    }

    #[test]
    fn unrenderable_titles_warn_but_do_not_refuse() {
        let c = Cart::parse("x", "-- title: Café ☕\nfunction _draw() end").unwrap();
        let w = c.warnings();
        assert!(!w.is_empty(), "an author should be told their title has a gap in it");
        assert!(w[0].contains("glyph"), "{w:?}");
    }

    #[test]
    fn an_ordinary_title_warns_about_nothing() {
        assert!(Cart::parse("x", OK).unwrap().warnings().is_empty());
    }

    #[test]
    fn the_scaffold_is_a_legal_cart_with_no_warnings() {
        // If `new` produced something `check` complained about, the first thing
        // every author did would fail.
        let src = scaffold("my game");
        let c = Cart::parse("my-game", &src).unwrap();
        assert_eq!(c.title, "my game");
        assert!(c.warnings().is_empty(), "{:?}", c.warnings());
        assert!(c.bytes < 1024, "a starting cart should be tiny, was {}", c.bytes);
    }
}
