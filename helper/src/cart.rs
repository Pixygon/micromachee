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

/// How much of a metadata value is kept.
pub const META_MAX: usize = 48;

#[derive(Debug, Clone)]
pub struct Cart {
    pub id: String,
    pub title: String,
    pub author: String,
    pub about: String,
    /// Whether a few seconds of this makes a round in Mega Micromachee. A
    /// nonogram or a farm is a fine game and a terrible ten seconds.
    pub in_mega: bool,
    pub code: String,
    pub bytes: usize,
}

impl Cart {
    /// Clean a string that came out of a cart before anything displays it.
    ///
    /// Metadata is the one part of a cart that is shown as TEXT rather than
    /// run, and after `sync` it can have come from a catalog on the internet.
    /// That makes it wire data, and it reaches places this program does not
    /// own: Qt `Text` fields default to `AutoText`, which sniffs a string for
    /// markup, so a title of `<img src="http://tracker/x">` would have the bar
    /// fetch that URL the moment it rendered. The panel also sets
    /// `Text.PlainText` for the same reason — but the tooltip goes through
    /// Omarchy's own internals, which neither this nor the panel controls, so
    /// the string has to be safe before it leaves here.
    ///
    /// Angle brackets go, because they are the whole of that sniff. Control
    /// characters go. So do the bidirectional overrides, which are invisible
    /// and let one name be drawn looking like another in a list of names.
    pub fn sanitize_display(raw: &str) -> String {
        let filtered: String = raw
            .chars()
            .filter_map(|c| {
                // A tab or a newline is a control character AND a word break.
                // Dropping it outright ran the words either side together, so
                // it becomes a space and the collapse below tidies up after.
                if c.is_whitespace() {
                    return Some(' ');
                }
                if c.is_control()
                    || c == '<'
                    || c == '>'
                    || matches!(c,
                        '\u{200B}'..='\u{200F}'
                        | '\u{202A}'..='\u{202E}'
                        | '\u{2066}'..='\u{2069}'
                        | '\u{FEFF}')
                {
                    return None;
                }
                Some(c)
            })
            .collect();
        // Collapse the whitespace too: a title padded with fifty spaces pushes
        // everything beside it off the shelf without containing anything.
        let collapsed: Vec<&str> = filtered.split_whitespace().collect();
        collapsed.join(" ").chars().take(META_MAX).collect()
    }

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
                        // Cleaned and capped here, which is the single door
                        // every title, author and about line comes through.
                        // Capped so a runaway header cannot push the shelf
                        // around. `check` says when it bites — a title clipped
                        // mid-word is the kind of thing that ships unnoticed
                        // because nothing anywhere complains.
                        let v = Self::sanitize_display(v);
                        if !v.is_empty() {
                            return Some(v);
                        }
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
            in_mega: meta("mega").map(|v| v != "no").unwrap_or(true),
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
        // Metadata is capped, and it used to be capped in silence: two of the
        // shipped carts had their `about` clipped mid-word — "does not bli" —
        // and nothing anywhere said so. A cap you cannot see is a bug you find
        // in production.
        for (field, value) in [
            ("title", &self.title),
            ("author", &self.author),
            ("about", &self.about),
        ] {
            if value.chars().count() == META_MAX {
                out.push(format!(
                    "`{field}` is exactly {META_MAX} characters, so it was probably cut short — \
                     shorten it and check the end is still there"
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
///
/// It teaches by example rather than by comment: colours named by role and
/// never by hue, `mid` for clamping, backwards iteration when removing from a
/// list, the HUD drawn last on its own ground, and O to restart. Those are the
/// habits every cart wants, so the first one an author sees already has them.
///
/// Built with a plain replace rather than `format!`: the body is full of Lua
/// table literals, and every `{` in it would have to be doubled.
pub fn scaffold(title: &str) -> String {
    const TEMPLATE: &str = r#"-- title: {{TITLE}}
-- author: {{AUTHOR}}
-- about: catch the falling ones

-- A whole game, so there is something on screen before you change anything.
-- Delete it a piece at a time.
--
-- 128x128, eight colours, 30 frames a second. Colours are INDEXES 0-7, dark to
-- light: 0 ground, 1 dim, 2 alert, 6 cool, 3 warm, 5 go, 4 bright, 7 light.
-- Never assume 2 is "red" — themes repaint every game, and only the order of
-- those eight is promised.

local x, drops, points, lives, tick

function _init()
  x      = 64
  drops  = {}
  points = 0
  lives  = 3
  tick   = 0
  score(0)
end

function _update()
  if lives <= 0 then
    if btnp(4) then _init() end   -- O restarts; every cart does it this way
    return
  end

  if btn(0) then x = x - 3 end    -- 0 left, 1 right, 2 up, 3 down, 4 O, 5 X
  if btn(1) then x = x + 3 end
  x = mid(8, x, 120)              -- mid(lo, value, hi) clamps

  tick = tick + 1
  if tick % 20 == 0 then
    drops[#drops + 1] = { x = 6 + rnd(116), y = 16, v = 1 + rnd(1.5) }
  end

  -- Backwards, so removing the one under the cursor cannot skip the next.
  for i = #drops, 1, -1 do
    local d = drops[i]
    d.y = d.y + d.v
    if d.y > 112 and d.y < 120 and d.x > x - 10 and d.x < x + 10 then
      points = points + 1
      score(points)
      table.remove(drops, i)
    elseif d.y > 128 then
      lives = lives - 1
      table.remove(drops, i)
    end
  end
end

function _draw()
  cls(0)

  for i = 1, #drops do
    circ(drops[i].x, drops[i].y, 2, 4)
  end
  rect(x - 10, 116, 20, 3, 7)

  -- The HUD is drawn last, on its own ground, so nothing falls through it.
  rect(0, 0, 128, 14, 0)
  line(0, 14, 127, 14, 1)
  print("SCORE " .. points, 2, 2, 7)
  for i = 1, lives do
    rect(120 - (i - 1) * 5, 3, 3, 3, 2)
  end

  if lives <= 0 then
    -- Boxed, or it lands on top of whatever is still moving.
    rect(28, 52, 72, 24, 0)
    rectb(28, 52, 72, 24, 2)
    print("GAME OVER", 46, 58, 7)
    print("PRESS O", 50, 66, 3)
  end
end
"#;
    TEMPLATE.replace("{{TITLE}}", title).replace("{{AUTHOR}}", "you")
}

#[cfg(test)]
mod display_tests {
    use super::*;

    fn titled(t: &str) -> String {
        Cart::parse("x", &format!("-- title: {t}\nfunction _draw() end\n")).unwrap().title
    }

    #[test]
    fn markup_never_survives_into_a_title() {
        // The actual attack: a Qt Text field on AutoText treats this as rich
        // text and fetches the image when it draws.
        let t = titled("<img src=\"http://tracker/x.png\">");
        assert!(!t.contains('<') && !t.contains('>'), "angle brackets survived: {t}");
        assert!(!t.to_lowercase().contains("<img"));
        for probe in ["<b>bold</b>", "<a href='http://x'>go</a>", "a<br>b"] {
            let got = titled(probe);
            assert!(!got.contains('<'), "{probe} left markup: {got}");
        }
    }

    #[test]
    fn invisible_characters_cannot_dress_one_name_as_another() {
        // Bidi overrides are not decoration; in a list of names they let one
        // entry be drawn looking like a different one.
        let t = titled("Snake\u{202E}elbuort\u{202C}");
        assert!(!t.contains('\u{202E}') && !t.contains('\u{202C}'), "{t:?}");
        assert!(!titled("A\u{200B}B").contains('\u{200B}'));
        assert!(!titled("A\u{FEFF}B").contains('\u{FEFF}'));
    }

    #[test]
    fn control_characters_and_padding_go() {
        assert_eq!(Cart::sanitize_display("a\tb\nc"), "a b c");
        assert_eq!(Cart::sanitize_display("   spaced   out   "), "spaced out");
        assert_eq!(Cart::sanitize_display(&" ".repeat(200)), "");
    }

    #[test]
    fn an_ordinary_title_is_left_alone() {
        // The check is worth nothing if it mangles the real ones.
        for ok in ["Serpent", "The Veil", "Farm of Arra", "Mega Micromachee", "Cat & Mouse"] {
            assert_eq!(Cart::sanitize_display(ok), ok, "{ok} was altered");
        }
        assert_eq!(titled("The Twins"), "The Twins");
    }

    #[test]
    fn the_length_bound_holds_after_cleaning() {
        // Cleaning happens first, so the cap has to be applied to what is left
        // or a title of 200 angle brackets would come out长 and empty-looking.
        let long = "x".repeat(500);
        assert_eq!(Cart::sanitize_display(&long).chars().count(), META_MAX);
        let mixed = format!("{}{}", "<".repeat(400), "y".repeat(400));
        assert!(Cart::sanitize_display(&mixed).chars().count() <= META_MAX);
    }
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
        assert!(c.bytes < 4096, "a starting cart should be small, was {}", c.bytes);
    }
}
