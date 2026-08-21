//! Mega Micromachee — the whole shelf, a few seconds at a time.
//!
//! Every cart in turn, ten seconds each, then nine, then eight. Survive and you
//! move on; fail and it costs a life. Every fifth round the clock gets shorter
//! and the games get faster, so the same cart you handled comfortably at round
//! two is a scramble at round twenty.
//!
//! It lives here rather than in a cart because a cart cannot load another cart —
//! and it should not be able to. The helper already loads carts and runs frames,
//! so the meta-game is a small state machine wrapped around the thing it
//! already does.
//!
//! **Speed is more updates, not a bigger step.** Running `_update` twice as
//! often makes a game faster while every cart's own arithmetic stays exactly as
//! its author wrote it; scaling a delta would need every cart to have been
//! written in terms of one, and none of them were.

use std::time::{SystemTime, UNIX_EPOCH};

use crate::cart::Cart;
use crate::console::{Screen, CHAR_WIDTH, H, W};
use crate::shelf;
use crate::vm::{Machine, Outcome, FPS};

/// The reserved id. There is no `mega.lua`; asking to play this builds the
/// meta-game instead, which is why the shelf and the panel need no special case.
pub const MEGA_ID: &str = "mega";
pub const MEGA_TITLE: &str = "Mega Micromachee";
pub const MEGA_ABOUT: &str = "every pearl, a few seconds each, faster and faster";

const LIVES: i32 = 3;
const INTRO_FRAMES: u32 = 60;
const CARD_FRAMES: u32 = 36;
const VERDICT_FRAMES: u32 = 27;

/// Rounds between each turn of the screw.
const STEP_EVERY: u32 = 5;
const START_SECONDS: f64 = 10.0;
const FLOOR_SECONDS: f64 = 5.0;
const SPEED_STEP: f64 = 0.15;
const MAX_SPEED: f64 = 2.5;

enum Phase {
    Intro,
    Card,
    Play,
    Verdict(bool),
    Over,
}

pub struct Mega {
    carts: Vec<Cart>,
    order: Vec<usize>,
    at: usize,
    round: u32,
    lives: i32,
    survived: i64,
    machine: Option<Machine>,
    phase: Phase,
    left: u32,
    /// Fractional updates carried between frames, so a speed of 1.5 really is
    /// three updates every two frames rather than one or two at random.
    carry: f64,
    seed: u64,
    pub out: Screen,
}

fn centre(text: &str, scale: i32) -> i32 {
    (W - text.chars().count() as i32 * CHAR_WIDTH * scale) / 2
}

impl Mega {
    pub fn new() -> Result<Mega, String> {
        let carts: Vec<Cart> = shelf::list().into_iter().filter(|c| c.id != MEGA_ID).collect();
        if carts.is_empty() {
            return Err("there are no carts to play — try `micromachee sync`".into());
        }
        let seed = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x2545_f491)
            | 1;
        let mut mega = Mega {
            order: (0..carts.len()).collect(),
            carts,
            at: 0,
            round: 0,
            lives: LIVES,
            survived: 0,
            machine: None,
            phase: Phase::Intro,
            left: INTRO_FRAMES,
            carry: 0.0,
            seed,
            out: Screen::new(),
        };
        mega.shuffle();
        Ok(mega)
    }

    fn rand(&mut self) -> u64 {
        // xorshift64*, the same one the console gives carts.
        self.seed ^= self.seed >> 12;
        self.seed ^= self.seed << 25;
        self.seed ^= self.seed >> 27;
        self.seed.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }

    fn shuffle(&mut self) {
        for i in (1..self.order.len()).rev() {
            let j = (self.rand() >> 33) as usize % (i + 1);
            self.order.swap(i, j);
        }
    }

    /// Seconds this round lasts: ten at the start, five once it has bitten.
    fn seconds(&self) -> f64 {
        (START_SECONDS - (self.round / STEP_EVERY) as f64).max(FLOOR_SECONDS)
    }

    fn speed(&self) -> f64 {
        (1.0 + (self.round / STEP_EVERY) as f64 * SPEED_STEP).min(MAX_SPEED)
    }

    fn current(&self) -> &Cart {
        &self.carts[self.order[self.at % self.order.len()]]
    }

    pub fn score(&self) -> i64 {
        self.survived
    }

    #[cfg(test)]
    pub fn over(&self) -> bool {
        matches!(self.phase, Phase::Over)
    }

    fn begin_round(&mut self) -> Result<(), String> {
        let cart = self.current().clone();
        // A fresh machine every round, and no saved state: a micro-game starts
        // from nothing, and a farm's coins have no business in here.
        self.machine = Some(Machine::load(&cart)?);
        if let Some(m) = &self.machine {
            m.init()?;
        }
        self.carry = 0.0;
        self.left = (self.seconds() * FPS as f64) as u32;
        self.phase = Phase::Play;
        Ok(())
    }

    fn next_round(&mut self) {
        self.round += 1;
        self.at += 1;
        if self.at % self.order.len() == 0 {
            self.shuffle();
        }
    }

    /// One frame. Errors are the meta-game's own; a cart that falls over just
    /// costs the round, because losing the whole run to somebody else's bug
    /// would be the wrong way round.
    pub fn step(&mut self, held: u8) -> Result<(), String> {
        match self.phase {
            Phase::Intro => {
                self.draw_intro();
                self.left = self.left.saturating_sub(1);
                if self.left == 0 {
                    self.phase = Phase::Card;
                    self.left = CARD_FRAMES;
                }
            }
            Phase::Card => {
                self.draw_card();
                self.left = self.left.saturating_sub(1);
                if self.left == 0 {
                    if let Err(e) = self.begin_round() {
                        // The cart would not even load; treat it as a miss.
                        let _ = e;
                        self.finish_round(false);
                    }
                }
            }
            Phase::Play => self.play_frame(held),
            Phase::Verdict(ok) => {
                self.draw_verdict(ok);
                self.left = self.left.saturating_sub(1);
                if self.left == 0 {
                    if self.lives <= 0 {
                        self.phase = Phase::Over;
                    } else {
                        self.next_round();
                        self.phase = Phase::Card;
                        self.left = CARD_FRAMES;
                    }
                }
            }
            Phase::Over => {
                self.draw_over();
                // O starts again.
                if held & (1 << 4) != 0 {
                    self.round = 0;
                    self.lives = LIVES;
                    self.survived = 0;
                    self.at = 0;
                    self.shuffle();
                    self.phase = Phase::Card;
                    self.left = CARD_FRAMES;
                }
            }
        }
        Ok(())
    }

    fn play_frame(&mut self, held: u8) {
        let mut lost = false;
        {
            let Some(m) = &self.machine else {
                self.finish_round(false);
                return;
            };
            m.set_held(held);
            // Faster means more turns of the cart's own loop per frame.
            self.carry += self.speed();
            let steps = self.carry.floor().max(1.0) as u32;
            self.carry -= steps as f64;
            for _ in 0..steps {
                if m.update().is_err() {
                    lost = true;
                    break;
                }
                if m.outcome.get() == Outcome::Lost {
                    lost = true;
                    break;
                }
            }
            if !lost && m.draw().is_err() {
                lost = true;
            }
            if !lost {
                self.out.px.copy_from_slice(&m.screen.borrow().px);
            }
        }

        if lost {
            self.finish_round(false);
            return;
        }

        self.left = self.left.saturating_sub(1);
        self.draw_hud();
        if self.left == 0 {
            self.finish_round(true);
        }
    }

    fn finish_round(&mut self, survived: bool) {
        self.machine = None;
        if survived {
            self.survived += 1;
        } else {
            self.lives -= 1;
        }
        self.phase = Phase::Verdict(survived);
        self.left = VERDICT_FRAMES;
    }

    // ── what it looks like ──────────────────────────────────────────────────

    /// A thin bar and three pips. The cart owns the screen; this is the least
    /// that can be laid over it and still answer "how long" and "how many left".
    fn draw_hud(&mut self) {
        let total = (self.seconds() * FPS as f64) as u32;
        let w = if total == 0 { 0 } else { (self.left * W as u32 / total) as i32 };
        self.out.rect(0, H - 2, W, 2, 0);
        let colour = if self.left < FPS { 2 } else { 5 };
        self.out.rect(0, H - 2, w, 2, colour);
        for i in 0..LIVES {
            let lit = i < self.lives;
            self.out.rect(W - 4 - i * 5, 1, 3, 3, if lit { 2 } else { 1 });
        }
    }

    fn draw_intro(&mut self) {
        self.out.cls(0);
        self.out.print("MEGA", centre("MEGA", 3), 34, 4, 3);
        self.out.print("MICROMACHEE", centre("MICROMACHEE", 1), 58, 7, 1);
        self.out.print("EVERY PEARL. NO TIME.", centre("EVERY PEARL. NO TIME.", 1), 78, 1, 1);
        let lives = format!("{LIVES} LIVES");
        self.out.print(&lives, centre(&lives, 1), 94, 2, 1);
    }

    fn draw_card(&mut self) {
        self.out.cls(0);
        let round = format!("ROUND {}", self.round + 1);
        self.out.print(&round, centre(&round, 1), 18, 1, 1);

        let title = self.current().title.clone();
        let scale = if title.chars().count() * 4 * 2 <= 120 { 2 } else { 1 };
        self.out.print(&title, centre(&title, scale), 46, 7, scale);

        let secs = format!("{} SECONDS", self.seconds() as i32);
        self.out.print(&secs, centre(&secs, 1), 74, 5, 1);

        if self.speed() > 1.0 {
            let sp = format!("SPEED {:.1}X", self.speed());
            self.out.print(&sp, centre(&sp, 1), 88, 3, 1);
        }
        for i in 0..LIVES {
            self.out.rect(W - 4 - i * 5, 1, 3, 3, if i < self.lives { 2 } else { 1 });
        }
    }

    fn draw_verdict(&mut self, ok: bool) {
        self.out.cls(0);
        let word = if ok { "SURVIVED" } else { "MISS" };
        self.out.print(word, centre(word, 2), 50, if ok { 5 } else { 2 }, 2);
        let n = format!("{} SURVIVED", self.survived);
        self.out.print(&n, centre(&n, 1), 76, 1, 1);
    }

    fn draw_over(&mut self) {
        self.out.cls(0);
        self.out.print("GAME OVER", centre("GAME OVER", 2), 40, 2, 2);
        let n = format!("{} ROUNDS", self.survived);
        self.out.print(&n, centre(&n, 1), 64, 7, 1);
        self.out.print("PRESS O", centre("PRESS O", 1), 84, 3, 1);
    }

    /// The shelf picture, drawn rather than stored — there is no mega.lua for a
    /// `_cover()` to live in.
    pub fn cover() -> Screen {
        let mut s = Screen::new();
        s.cls(0);
        for i in 0..6 {
            let x = 8 + (i % 3) * 40;
            let y = 12 + (i / 3) * 34;
            s.rect(x, y, 34, 26, 1);
            s.rect(x + 3, y + 3, 28, 20, 0);
            s.print("?", x + 14, y + 9, 2 + i % 5, 1);
        }
        s.rect(0, 82, W, 46, 0);
        s.print("MEGA", centre("MEGA", 3), 88, 3, 3);
        s.print("MICROMACHEE", centre("MICROMACHEE", 1), 112, 7, 1);
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake(id: &str, code: &str) -> Cart {
        Cart::parse(id, code).unwrap()
    }

    fn rig(carts: Vec<Cart>) -> Mega {
        let mut m = Mega {
            order: (0..carts.len()).collect(),
            carts,
            at: 0,
            round: 0,
            lives: LIVES,
            survived: 0,
            machine: None,
            phase: Phase::Card,
            left: 1,
            carry: 0.0,
            seed: 12345,
            out: Screen::new(),
        };
        m.left = 1;
        m
    }

    fn survivor() -> Cart {
        fake("ok", "-- title: Ok\nfunction _draw() cls(3) end\n")
    }

    fn loser() -> Cart {
        fake("bad", "-- title: Bad\nfunction _update() lose() end\nfunction _draw() cls(2) end\n")
    }

    /// Run frames until the phase stops being Play, or we give up.
    fn run(m: &mut Mega, frames: u32) {
        for _ in 0..frames {
            m.step(0).unwrap();
        }
    }

    #[test]
    fn surviving_the_clock_moves_you_on_without_costing_a_life() {
        let mut m = rig(vec![survivor()]);
        run(&mut m, 1 + (START_SECONDS * FPS as f64) as u32 + 2);
        assert_eq!(m.lives, LIVES, "a survived round must not cost a life");
        assert_eq!(m.survived, 1);
    }

    #[test]
    fn a_cart_that_says_it_lost_costs_a_life_at_once() {
        let mut m = rig(vec![loser()]);
        // The card is one frame here; the very next update calls lose().
        run(&mut m, 4);
        assert_eq!(m.lives, LIVES - 1, "losing must cost exactly one life");
        assert_eq!(m.survived, 0, "and must not count as survived");
    }

    #[test]
    fn three_misses_ends_the_run() {
        let mut m = rig(vec![loser()]);
        for _ in 0..LIVES {
            run(&mut m, VERDICT_FRAMES + CARD_FRAMES + 4);
        }
        assert!(m.over(), "after {LIVES} misses it should be over, lives={}", m.lives);
    }

    #[test]
    fn it_gets_shorter_and_faster_every_fifth_round_and_then_stops() {
        let mut m = rig(vec![survivor()]);
        assert_eq!(m.seconds(), START_SECONDS);
        assert_eq!(m.speed(), 1.0);

        m.round = STEP_EVERY;
        assert_eq!(m.seconds(), START_SECONDS - 1.0, "one second shorter");
        assert!(m.speed() > 1.0, "and faster");

        m.round = STEP_EVERY * 4;
        assert!(m.seconds() < START_SECONDS && m.seconds() >= FLOOR_SECONDS);

        // It must bottom out rather than reaching zero seconds and no game.
        m.round = 10_000;
        assert_eq!(m.seconds(), FLOOR_SECONDS, "the clock has a floor");
        assert_eq!(m.speed(), MAX_SPEED, "and so does the speed");
    }

    #[test]
    fn speed_really_is_more_turns_of_the_cart() {
        // The whole mechanism, so it gets a test: a cart reports its own update
        // count through score(), and a later round must tick it faster.
        let counter = fake(
            "count",
            "n = 0\nfunction _update() n = n + 1 score(n) end\nfunction _draw() cls(0) end\n",
        );

        let mut slow = rig(vec![counter.clone()]);
        run(&mut slow, 11); // one frame of card, ten of play
        let slow_ticks = slow.machine.as_ref().unwrap().score.get();

        let mut fast = rig(vec![counter]);
        fast.round = STEP_EVERY * 10; // well into the speed-up
        run(&mut fast, 11);
        let fast_ticks = fast.machine.as_ref().unwrap().score.get();

        assert_eq!(slow_ticks, 10, "ten frames of play is ten updates at 1x");
        assert!(
            fast_ticks > slow_ticks,
            "at {:.2}x the cart should have ticked more than {slow_ticks}, got {fast_ticks}",
            fast.speed()
        );
    }

    #[test]
    fn a_cart_that_falls_over_costs_the_round_not_the_run() {
        let boom = fake("boom", "-- title: Boom\nfunction _update() error('nope') end\nfunction _draw() end\n");
        let mut m = rig(vec![boom]);
        run(&mut m, 4);
        assert_eq!(m.lives, LIVES - 1);
        assert!(!m.over(), "one broken cart must not end the whole run");
    }

    #[test]
    fn every_cart_gets_a_turn_before_any_repeats() {
        let carts = vec![
            fake("a", "-- title: A\nfunction _draw() end\n"),
            fake("b", "-- title: B\nfunction _draw() end\n"),
            fake("c", "-- title: C\nfunction _draw() end\n"),
        ];
        let mut m = rig(carts);
        let mut seen = std::collections::HashSet::new();
        for _ in 0..3 {
            seen.insert(m.current().id.clone());
            m.next_round();
        }
        assert_eq!(seen.len(), 3, "a rotation must use the whole shelf");
    }
}
