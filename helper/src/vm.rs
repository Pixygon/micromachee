//! The machine that runs a cart.
//!
//! Lua, because the entire point of this console is that writing a game for it
//! should be trivial — and Lua with a PICO-8-shaped API is the one dialect that
//! both people and language models already write fluently, without reading
//! anything first.
//!
//! Two limits are not optional, because a cart is a stranger's code running in
//! your bar:
//!
//!   * **An instruction budget per frame.** `while true do end` is one
//!     keystroke away in any language. Without a budget it locks the widget,
//!     and the user's only recourse is killing the panel.
//!   * **A memory ceiling.** A runaway table should end the cart, not the
//!     session.
//!
//! Neither is a sandbox in the security sense — this is Lua with the standard
//! library — and the README says so plainly rather than implying otherwise.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use mlua::{Function, HookTriggers, Lua, LuaOptions, StdLib, VmState};

use crate::cart::Cart;
use crate::console::Screen;

/// Instructions a single `_update` or `_draw` may spend. Generous — a busy
/// frame is thousands, not millions — while still catching a loop that never
/// ends within a fraction of a second.
const FRAME_INSTRUCTION_BUDGET: u32 = 2_000_000;
const HOOK_EVERY: u32 = 50_000;

/// Memory a cart may hold. A 128×128 game needs a rounding error of this.
const MEMORY_LIMIT: usize = 16 * 1024 * 1024;

pub const FPS: u32 = 30;

/// What a cart has said about how the player is doing. Every cart tracks this
/// already — as `alive`, `over`, `dead`, `lives`, a different local each time —
/// and none of it is visible from out here. So a cart that wants to be playable
/// inside something bigger says so once, and the console can finally tell the
/// difference between a game being lost and a game merely being watched.
#[derive(Clone, Copy, PartialEq, Debug, Default)]
pub enum Outcome {
    #[default]
    Playing,
    Lost,
    Won,
}

#[derive(Default)]
pub struct Input {
    /// Bit i set = button i held. 0 left, 1 right, 2 up, 3 down, 4 O, 5 X.
    pub held: u8,
    pub last: u8,
}

impl Input {
    pub fn pressed(&self, i: u8) -> bool {
        self.held & (1 << i) != 0 && self.last & (1 << i) == 0
    }
}

pub struct Machine {
    lua: Lua,
    pub screen: Rc<RefCell<Screen>>,
    pub input: Rc<RefCell<Input>>,
    pub frame: Rc<Cell<u64>>,
    pub score: Rc<Cell<i64>>,
    /// What the cart has saved, and whether it has changed since it was written
    /// out. A farm that grows while the widget is closed needs somewhere to put
    /// the time it was last looked at.
    pub saved: Rc<RefCell<serde_json::Map<String, serde_json::Value>>>,
    pub dirty: Rc<Cell<bool>>,
    pub outcome: Rc<Cell<Outcome>>,
    /// Whether text is rendered in the Ydrast on the way to the screen.
    tongue: Rc<Cell<bool>>,
    budget: Rc<Cell<u32>>,
}

impl Machine {
    pub fn load(cart: &Cart) -> Result<Machine, String> {
        Self::load_with(cart, serde_json::Map::new())
    }

    pub fn load_with(
        cart: &Cart,
        saved_in: serde_json::Map<String, serde_json::Value>,
    ) -> Result<Machine, String> {
        // Only the libraries a game actually needs. `Lua::new()` would also
        // bring `io`, `os` and `package`, and a cart could then write to your
        // disk — which was true and demonstrated: a test cart created a file in
        // /tmp and the console let it. Carts arrive from a CDN and the pitch is
        // "drop a .lua in a folder", so that is not a footnote to document, it
        // is a hole to close. Nothing in any real cart wanted them.
        let lua = Lua::new_with(
            StdLib::MATH | StdLib::STRING | StdLib::TABLE,
            LuaOptions::default(),
        )
        .map_err(|e| e.to_string())?;
        lua.set_memory_limit(MEMORY_LIMIT).ok();

        // `dofile` and `loadfile` live in the base library, which is always
        // present, and both open files. `load` stays: compiling a string is
        // harmless once there is nothing to reach.
        {
            let g = lua.globals();
            for name in ["dofile", "loadfile", "collectgarbage"] {
                let _ = g.set(name, mlua::Value::Nil);
            }
        }

        let screen = Rc::new(RefCell::new(Screen::new()));
        let input = Rc::new(RefCell::new(Input::default()));
        let frame = Rc::new(Cell::new(0u64));
        let score = Rc::new(Cell::new(0i64));
        let budget = Rc::new(Cell::new(FRAME_INSTRUCTION_BUDGET));
        let saved = Rc::new(RefCell::new(saved_in));
        let dirty = Rc::new(Cell::new(false));
        let outcome = Rc::new(Cell::new(Outcome::Playing));
        let tongue = Rc::new(Cell::new(false));
        let rng = Rc::new(Cell::new(0x2545_f491_4f6c_dd1du64));

        {
            let budget = budget.clone();
            lua.set_hook(HookTriggers::new().every_nth_instruction(HOOK_EVERY), move |_, _| {
                let left = budget.get().saturating_sub(HOOK_EVERY);
                budget.set(left);
                if left == 0 {
                    // Surfaced to the player as "this frame never finished",
                    // which is what it looks like from outside.
                    return Err(mlua::Error::runtime("a frame ran forever (endless loop?)"));
                }
                Ok(VmState::Continue)
            });
        }

        let g = lua.globals();
        macro_rules! api {
            ($name:literal, $f:expr) => {
                g.set($name, lua.create_function($f).map_err(|e| e.to_string())?)
                    .map_err(|e| e.to_string())?;
            };
        }

        // Coordinates arrive as Lua numbers and are floored, so a game may do
        // its own maths in floats and never think about it.
        let n = |v: f64| v.floor() as i32;

        {
            let s = screen.clone();
            api!("cls", move |_, c: Option<f64>| {
                s.borrow_mut().cls(c.map(n).unwrap_or(0));
                Ok(())
            });
        }
        {
            let s = screen.clone();
            api!("pset", move |_, (x, y, c): (f64, f64, f64)| {
                s.borrow_mut().pset(n(x), n(y), n(c));
                Ok(())
            });
        }
        {
            let s = screen.clone();
            api!("pget", move |_, (x, y): (f64, f64)| Ok(s.borrow().pget(n(x), n(y)) as i64));
        }
        {
            let s = screen.clone();
            api!("rect", move |_, (x, y, w, h, c): (f64, f64, f64, f64, f64)| {
                s.borrow_mut().rect(n(x), n(y), n(w), n(h), n(c));
                Ok(())
            });
        }
        {
            let s = screen.clone();
            api!("rectb", move |_, (x, y, w, h, c): (f64, f64, f64, f64, f64)| {
                s.borrow_mut().rectb(n(x), n(y), n(w), n(h), n(c));
                Ok(())
            });
        }
        {
            let s = screen.clone();
            api!("line", move |_, (x0, y0, x1, y1, c): (f64, f64, f64, f64, f64)| {
                s.borrow_mut().line(n(x0), n(y0), n(x1), n(y1), n(c));
                Ok(())
            });
        }
        {
            let s = screen.clone();
            api!("circ", move |_, (x, y, r, c): (f64, f64, f64, f64)| {
                s.borrow_mut().circ(n(x), n(y), n(r), n(c));
                Ok(())
            });
        }
        {
            let s = screen.clone();
            api!("circb", move |_, (x, y, r, c): (f64, f64, f64, f64)| {
                s.borrow_mut().circb(n(x), n(y), n(r), n(c));
                Ok(())
            });
        }
        {
            let s = screen.clone();
            let tg = tongue.clone();
            api!("print", move |_, (t, x, y, c, scale): (mlua::Value, f64, f64, Option<f64>, Option<f64>)| {
                let text = match t {
                    mlua::Value::String(s) => s.to_string_lossy().to_string(),
                    mlua::Value::Integer(i) => i.to_string(),
                    mlua::Value::Number(f) => {
                        if f.fract() == 0.0 { format!("{}", f as i64) } else { format!("{f}") }
                    }
                    mlua::Value::Nil => "NIL".into(),
                    mlua::Value::Boolean(b) => b.to_string(),
                    _ => "?".into(),
                };
                // Every word a cart prints passes through here, which is the
                // one place the console can speak a different language without
                // a single cart knowing about it.
                let text = if tg.get() { crate::ydrast::render(&text) } else { text };
                // The fifth argument is optional and defaults to 1, so every
                // cart written before it existed prints exactly as it did.
                s.borrow_mut()
                    .print(&text, n(x), n(y), c.map(n).unwrap_or(7), scale.map(n).unwrap_or(1));
                Ok(())
            });
        }
        {
            let i = input.clone();
            api!("btn", move |_, b: f64| Ok(i.borrow().held & (1 << (n(b).clamp(0, 5))) != 0));
        }
        {
            let i = input.clone();
            api!("btnp", move |_, b: f64| Ok(i.borrow().pressed(n(b).clamp(0, 5) as u8)));
        }
        {
            let f = frame.clone();
            api!("t", move |_, ()| Ok(f.get() as f64 / FPS as f64));
        }
        {
            let r = rng.clone();
            api!("rnd", move |_, max: Option<f64>| {
                // xorshift64*, so the console carries no RNG dependency and
                // every machine agrees on what `rnd` means.
                let mut x = r.get();
                x ^= x >> 12;
                x ^= x << 25;
                x ^= x >> 27;
                r.set(x);
                let unit = ((x.wrapping_mul(0x2545_f491_4f6c_dd1d) >> 11) as f64) / ((1u64 << 53) as f64);
                Ok(unit * max.unwrap_or(1.0))
            });
        }
        // Returns an INTEGER, not a float. `print("SCORE " .. flr(n), …)` is
        // the most common line anybody writes on this console, and Lua
        // stringifies a float as "30.0" before `print` ever sees it — so a
        // floating flr puts a ".0" in the corner of nearly every first draft.
        api!("flr", |_, x: f64| Ok(x.floor() as i64));
        // Integers in, integer out — the same rule `flr` follows, and for the
        // same reason: a cart clamps a grid coordinate and then builds a key
        // out of it, and a float turns "p0" into "p0.0". Nothing concatenated
        // this result until a game started saving one plot per square, so the
        // flaw sat here unnoticed the whole time.
        api!("mid", |_, (a, b, c): (mlua::Value, mlua::Value, mlua::Value)| {
            let num = |v: &mlua::Value| match v {
                mlua::Value::Integer(i) => *i as f64,
                mlua::Value::Number(f) => *f,
                _ => 0.0,
            };
            let whole = matches!(a, mlua::Value::Integer(_))
                && matches!(b, mlua::Value::Integer(_))
                && matches!(c, mlua::Value::Integer(_));
            let (x, y, z) = (num(&a), num(&b), num(&c));
            let (lo, hi) = if x <= z { (x, z) } else { (z, x) };
            let r = y.clamp(lo, hi);
            Ok(if whole {
                mlua::Value::Integer(r as i64)
            } else {
                mlua::Value::Number(r)
            })
        });
        {
            // Persistent state, so a game can pick up where it was left. Only
            // numbers and strings: a save file that can hold a table is a save
            // file that can hold a cycle, and this one has to survive being
            // written to disk by a widget that may be killed at any moment.
            let (st, dr) = (saved.clone(), dirty.clone());
            api!("save", move |_, (k, v): (String, mlua::Value)| {
                let val = match v {
                    mlua::Value::Integer(i) => serde_json::json!(i),
                    mlua::Value::Number(f) => serde_json::json!(f),
                    mlua::Value::String(s) => serde_json::json!(s.to_string_lossy()),
                    mlua::Value::Boolean(b) => serde_json::json!(b),
                    mlua::Value::Nil => serde_json::Value::Null,
                    _ => return Err(mlua::Error::runtime("save() takes a number, string or boolean")),
                };
                st.borrow_mut().insert(k, val);
                dr.set(true);
                Ok(())
            });
        }
        {
            let st = saved.clone();
            api!("load", move |lua, k: String| {
                let store = st.borrow();
                Ok(match store.get(&k) {
                    Some(serde_json::Value::Number(n)) => {
                        if let Some(i) = n.as_i64() {
                            mlua::Value::Integer(i)
                        } else {
                            mlua::Value::Number(n.as_f64().unwrap_or(0.0))
                        }
                    }
                    Some(serde_json::Value::String(s)) => {
                        mlua::Value::String(lua.create_string(s.as_str())?)
                    }
                    Some(serde_json::Value::Bool(b)) => mlua::Value::Boolean(*b),
                    _ => mlua::Value::Nil,
                })
            });
        }
        {
            let o = outcome.clone();
            api!("lose", move |_, ()| {
                o.set(Outcome::Lost);
                Ok(())
            });
        }
        {
            let o = outcome.clone();
            api!("win", move |_, ()| {
                o.set(Outcome::Won);
                Ok(())
            });
        }
        // Wall-clock seconds. `t()` is time inside this run; this is time in the
        // world, so a crop can grow while nobody is looking at it.
        api!("now", |_, ()| {
            Ok(std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as f64)
                .unwrap_or(0.0))
        });
        {
            let sc = score.clone();
            api!("score", move |_, v: f64| {
                sc.set(v.floor() as i64);
                Ok(())
            });
        }

        lua.load(&cart.code)
            .set_name(cart.id.as_str())
            .exec()
            .map_err(|e| tidy(&e.to_string()))?;

        Ok(Machine { lua, screen, input, frame, score, saved, dirty, outcome, tongue, budget })
    }

    fn call(&self, name: &str) -> Result<(), String> {
        self.budget.set(FRAME_INSTRUCTION_BUDGET);
        let g = self.lua.globals();
        let Ok(f) = g.get::<Function>(name) else {
            return Ok(()); // an absent callback is simply not called
        };
        f.call::<()>(()).map_err(|e| tidy(&e.to_string()))
    }

    pub fn init(&self) -> Result<(), String> {
        // Starting over is starting over: a cart that restarts itself after a
        // game over must not still be reported as lost.
        self.clear_outcome();
        self.call("_init")
    }

    pub fn update(&self) -> Result<(), String> {
        let r = self.call("_update");
        let mut i = self.input.borrow_mut();
        i.last = i.held;
        r
    }

    pub fn draw(&self) -> Result<(), String> {
        let r = self.call("_draw");
        self.frame.set(self.frame.get() + 1);
        r
    }

    /// Whether the cart draws its own cover.
    pub fn has_cover(&self) -> bool {
        self.lua.globals().get::<Function>("_cover").is_ok()
    }

    /// Draw the shelf picture. `_init` is expected to have run first, so a
    /// cover can use the same state and helpers the game does — it is the same
    /// machine, with the same eight colours, not a separate asset pipeline.
    pub fn cover(&self) -> Result<(), String> {
        self.call("_cover")
    }

    /// Back to Playing, so a cart that restarts itself is not still "lost".
    pub fn clear_outcome(&self) {
        self.outcome.set(Outcome::Playing);
    }

    pub fn set_tongue(&self, on: bool) {
        self.tongue.set(on);
    }

    pub fn set_held(&self, held: u8) {
        self.input.borrow_mut().held = held;
    }
}

/// Lua errors arrive with a traceback attached. The first line is the one an
/// author can act on; the rest is noise in a 128-pixel-wide panel.
fn tidy(msg: &str) -> String {
    let first = msg.lines().next().unwrap_or(msg).trim();
    first.strip_prefix("runtime error: ").unwrap_or(first).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cart::Cart;

    fn machine(code: &str) -> Machine {
        Machine::load(&Cart::parse("t", code).unwrap()).unwrap()
    }

    #[test]
    fn a_cart_can_draw() {
        let m = machine("function _draw() cls(3) end");
        m.draw().unwrap();
        assert!(m.screen.borrow().px.iter().all(|&p| p == 3));
    }

    #[test]
    fn init_update_draw_all_run() {
        let m = machine(
            "n=0
             function _init() n=1 end
             function _update() n=n+1 end
             function _draw() cls(0) rect(0,0,n,1,5) end",
        );
        m.init().unwrap();
        m.update().unwrap();
        m.draw().unwrap();
        assert_eq!(m.screen.borrow().pget(1, 0), 5, "n should be 2 by draw time");
    }

    #[test]
    fn the_tongue_changes_what_reaches_the_screen_not_the_cart() {
        // A cart never learns which language it is printing in — the same call
        // draws different pixels, and nothing in the game changes.
        let m = machine("function _draw() cls(0) print('THE THREAD IS TIME', 0, 0, 7) end");
        m.draw().unwrap();
        let plain = m.screen.borrow().px.clone();
        m.set_tongue(true);
        m.draw().unwrap();
        assert_ne!(plain, m.screen.borrow().px, "the ydrast must look different");
        m.set_tongue(false);
        m.draw().unwrap();
        assert_eq!(plain, m.screen.borrow().px, "and turning it off must restore it exactly");
    }

    #[test]
    fn a_cart_can_say_it_lost() {
        let m = machine(
            "n = 0\nfunction _update() n = n + 1 if n > 2 then lose() end end\n\
             function _draw() cls(0) end",
        );
        m.init().unwrap();
        assert_eq!(m.outcome.get(), Outcome::Playing);
        m.update().unwrap();
        m.update().unwrap();
        assert_eq!(m.outcome.get(), Outcome::Playing, "not lost yet");
        m.update().unwrap();
        assert_eq!(m.outcome.get(), Outcome::Lost);
        m.clear_outcome();
        assert_eq!(m.outcome.get(), Outcome::Playing);
    }

    #[test]
    fn a_cart_that_never_says_anything_is_simply_playing() {
        // Every cart written before `lose()` existed has to keep working.
        let m = machine("function _draw() cls(0) end");
        m.init().unwrap();
        m.update().unwrap();
        m.draw().unwrap();
        assert_eq!(m.outcome.get(), Outcome::Playing);
    }

    #[test]
    fn a_cart_can_draw_its_own_cover() {
        let m = machine("function _cover() cls(6) end function _draw() cls(0) end");
        assert!(m.has_cover());
        m.init().unwrap();
        m.cover().unwrap();
        assert!(m.screen.borrow().px.iter().all(|&p| p == 6), "the cover drew, not _draw");
    }

    #[test]
    fn a_cart_without_a_cover_says_so() {
        let m = machine("function _draw() cls(1) end");
        assert!(!m.has_cover(), "nothing to fall back from otherwise");
    }

    #[test]
    fn a_missing_callback_is_not_an_error() {
        let m = machine("function _draw() cls(1) end");
        m.init().unwrap();
        m.update().unwrap();
    }

    #[test]
    fn an_endless_loop_ends_the_frame_not_the_console() {
        // The whole reason the budget exists. This must return, and quickly.
        let m = machine("function _draw() while true do end end");
        let started = std::time::Instant::now();
        let err = m.draw().unwrap_err();
        assert!(err.contains("forever"), "{err}");
        assert!(started.elapsed().as_secs() < 5, "took {:?}", started.elapsed());
    }

    #[test]
    fn the_budget_refills_every_frame() {
        // A game that legitimately does a lot of work each frame must not run
        // out after a few seconds of play.
        let m = machine("function _draw() for i=1,20000 do pset(i%128, 4, 2) end end");
        for _ in 0..40 {
            m.draw().unwrap();
        }
    }

    #[test]
    fn a_cart_cannot_reach_the_filesystem() {
        // Demonstrated before it was fixed: a cart opened /tmp and wrote to it.
        for probe in ["io", "os", "package", "require", "dofile", "loadfile"] {
            let m = machine(&format!("seen = {probe} ~= nil\nfunction _draw() end"));
            assert!(
                !m.lua.globals().get::<bool>("seen").unwrap(),
                "`{probe}` is reachable from a cart"
            );
        }
    }

    #[test]
    fn the_libraries_a_game_actually_needs_are_present() {
        let m = machine(
            "a = math.floor(2.5) b = #table.concat({'x','y'}) c = string.rep('z', 3)
             function _draw() end",
        );
        let g = m.lua.globals();
        assert_eq!(g.get::<i64>("a").unwrap(), 2);
        assert_eq!(g.get::<i64>("b").unwrap(), 2);
        assert_eq!(g.get::<String>("c").unwrap(), "zzz");
    }

    #[test]
    fn a_lua_error_is_reported_in_one_readable_line() {
        let m = machine("function _draw() error('the wheels came off') end");
        let err = m.draw().unwrap_err();
        assert!(err.contains("the wheels came off"), "{err}");
        assert!(!err.contains('\n'), "the panel shows one line: {err:?}");
    }

    #[test]
    fn a_cart_that_does_not_compile_fails_at_load() {
        let err = Machine::load(&Cart::parse("bad", "function _draw( end").unwrap())
            .err()
            .expect("a syntax error must fail at load, not at the first frame");
        assert!(!err.is_empty());
    }

    #[test]
    fn buttons_report_held_and_pressed() {
        let m = machine(
            "held=false pressed=false
             function _update() held=btn(1) pressed=btnp(1) end
             function _draw() end",
        );
        m.set_held(0b10);
        m.update().unwrap();
        assert!(m.lua.globals().get::<bool>("held").unwrap());
        assert!(m.lua.globals().get::<bool>("pressed").unwrap(), "first frame is a press");
        m.update().unwrap();
        assert!(m.lua.globals().get::<bool>("held").unwrap(), "still held");
        assert!(!m.lua.globals().get::<bool>("pressed").unwrap(), "no longer newly pressed");
    }

    #[test]
    fn rnd_stays_in_range() {
        let m = machine("v=0 lo=99 hi=-99\nfunction _draw() for i=1,500 do v=rnd(10) if v<lo then lo=v end if v>hi then hi=v end end end");
        m.draw().unwrap();
        let lo: f64 = m.lua.globals().get("lo").unwrap();
        let hi: f64 = m.lua.globals().get("hi").unwrap();
        assert!(lo >= 0.0 && hi < 10.0, "rnd(10) gave {lo}..{hi}");
    }

    #[test]
    fn flr_gives_an_integer_you_can_concatenate() {
        // The bug this guards: "SCORE 30.0" in the corner of every new game.
        let m = machine("s = \"\" .. flr(3.7)\nneg = \"\" .. flr(-1.2)\nfunction _draw() end");
        assert_eq!(m.lua.globals().get::<String>("s").unwrap(), "3");
        assert_eq!(m.lua.globals().get::<String>("neg").unwrap(), "-2");
    }

    #[test]
    fn mid_clamps_the_way_a_game_expects() {
        let m = machine("a=mid(4,999,123) b=mid(4,-5,123) c=mid(4,60,123)\nfunction _draw() end");
        let g = m.lua.globals();
        assert_eq!(g.get::<f64>("a").unwrap(), 123.0);
        assert_eq!(g.get::<f64>("b").unwrap(), 4.0);
        assert_eq!(g.get::<f64>("c").unwrap(), 60.0);
    }

    #[test]
    fn mid_keeps_integers_whole_so_they_can_be_concatenated() {
        let m = machine(
            "a = '' .. mid(0, 2, 5)\n             b = '' .. mid(0, 7, 5)\n\
             c = '' .. mid(0.0, 2.5, 5.0)\n\
             function _draw() end",
        );
        let g = m.lua.globals();
        assert_eq!(g.get::<String>("a").unwrap(), "2", "an in-range integer must stay whole");
        assert_eq!(g.get::<String>("b").unwrap(), "5", "a clamped integer must stay whole");
        assert_eq!(g.get::<String>("c").unwrap(), "2.5", "floats are still floats");
    }

    #[test]
    fn print_takes_an_optional_scale_and_old_carts_are_unaffected() {
        let m = machine(
            "function _draw() cls(0) print('A', 0, 0, 7) print('A', 40, 0, 7, 3) end",
        );
        m.draw().unwrap();
        let s = m.screen.borrow();
        // 1x: the glyph is five rows tall. 3x: fifteen.
        assert_eq!(s.pget(1, 0), 7, "1x drew");
        assert_eq!(s.pget(1, 6), 0, "1x stopped at five rows");
        assert_eq!(s.pget(41, 13), 7, "3x is still drawing at row four (y 12-14)");
    }

    #[test]
    fn print_accepts_numbers_as_well_as_strings() {
        // Every game prints a score, and a score is a number.
        let m = machine("function _draw() cls(0) print(42, 4, 4, 7) print(1.5, 4, 12, 7) end");
        m.draw().unwrap();
        assert!(m.screen.borrow().px.iter().any(|&p| p == 7));
    }

    #[test]
    fn t_advances_with_frames() {
        let m = machine("v=0 function _draw() v=t() end");
        for _ in 0..FPS {
            m.draw().unwrap();
        }
        let v: f64 = m.lua.globals().get("v").unwrap();
        assert!((v - (FPS - 1) as f64 / FPS as f64).abs() < 1e-9, "t() was {v}");
    }

    #[test]
    fn score_is_readable_by_the_console() {
        let m = machine("function _draw() score(1234) end");
        m.draw().unwrap();
        assert_eq!(m.score.get(), 1234);
    }
}
