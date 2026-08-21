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

use mlua::{Function, HookTriggers, Lua, VmState};

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
    budget: Rc<Cell<u32>>,
}

impl Machine {
    pub fn load(cart: &Cart) -> Result<Machine, String> {
        let lua = Lua::new();
        lua.set_memory_limit(MEMORY_LIMIT).ok();

        let screen = Rc::new(RefCell::new(Screen::new()));
        let input = Rc::new(RefCell::new(Input::default()));
        let frame = Rc::new(Cell::new(0u64));
        let score = Rc::new(Cell::new(0i64));
        let budget = Rc::new(Cell::new(FRAME_INSTRUCTION_BUDGET));
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
            api!("print", move |_, (t, x, y, c): (mlua::Value, f64, f64, Option<f64>)| {
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
                s.borrow_mut().print(&text, n(x), n(y), c.map(n).unwrap_or(7));
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
        api!("mid", |_, (a, b, c): (f64, f64, f64)| {
            let (lo, hi) = if a <= c { (a, c) } else { (c, a) };
            Ok(b.clamp(lo, hi))
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

        Ok(Machine { lua, screen, input, frame, score, budget })
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
