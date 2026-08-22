//! The sound the console makes.
//!
//! There is no audio library here for the same reason there is no PNG library:
//! the format is a header and then the samples, and writing it is smaller than
//! depending on something that writes it. A RIFF header is 44 bytes.
//!
//! Eight sounds, generated rather than stored, so nothing ships a binary blob
//! and a theme's worth of audio is a table of numbers you can read. They are
//! deliberately a **fixed bank**: a cart says `sfx(2)` and means "the explode
//! one", exactly as it says `7` and means "the light one". A cart that could
//! specify frequencies would be a cart that sounds different from the console
//! it is running on, and the whole point of the eight colours is that it
//! cannot do that with the picture either.
//!
//! Everything is a square wave or white noise, because that is what a console
//! this size would have had, and because a square wave is one comparison per
//! sample.

pub const RATE: u32 = 22_050;

/// The bank. A cart passes the index; `sfx(8)` and up wrap, the way colours do.
pub const NAMES: [&str; 8] =
    ["blip", "hit", "boom", "pickup", "jump", "hurt", "win", "lose"];

/// One piece of a sound: a square-wave sweep, or noise, or silence.
struct Seg {
    secs: f32,
    from: f32,
    to: f32,
    /// 0.0 pure square, 1.0 pure noise.
    grit: f32,
    /// Amplitude at the start and end of the segment.
    amp0: f32,
    amp1: f32,
}

const fn seg(secs: f32, from: f32, to: f32, grit: f32, amp0: f32, amp1: f32) -> Seg {
    Seg { secs, from, to, grit, amp0, amp1 }
}

fn recipe(which: usize) -> Vec<Seg> {
    match which & 7 {
        // A cursor moving, a shot leaving. Short enough to fire every frame
        // without becoming a tone.
        0 => vec![seg(0.045, 900.0, 1250.0, 0.0, 0.55, 0.0)],
        // Something took a hit: down, fast.
        1 => vec![seg(0.085, 520.0, 150.0, 0.15, 0.65, 0.0)],
        // Something stopped existing.
        2 => vec![seg(0.30, 200.0, 40.0, 0.85, 0.8, 0.0)],
        // Picked up. Three steps up reads as a reward in any key.
        3 => vec![
            seg(0.045, 660.0, 660.0, 0.0, 0.5, 0.5),
            seg(0.045, 880.0, 880.0, 0.0, 0.5, 0.5),
            seg(0.075, 1320.0, 1320.0, 0.0, 0.55, 0.0),
        ],
        // Leaving the ground.
        4 => vec![seg(0.12, 300.0, 760.0, 0.0, 0.5, 0.05)],
        // You took the hit. Noisier and lower than 1, so the two are never
        // confused in the middle of a fight.
        5 => vec![seg(0.24, 420.0, 90.0, 0.5, 0.7, 0.0)],
        // Finished it.
        6 => vec![
            seg(0.09, 523.0, 523.0, 0.0, 0.5, 0.5),
            seg(0.09, 659.0, 659.0, 0.0, 0.5, 0.5),
            seg(0.09, 784.0, 784.0, 0.0, 0.5, 0.5),
            seg(0.20, 1046.0, 1046.0, 0.0, 0.55, 0.0),
        ],
        // Did not.
        _ => vec![
            seg(0.10, 440.0, 440.0, 0.0, 0.5, 0.5),
            seg(0.10, 349.0, 349.0, 0.0, 0.5, 0.5),
            seg(0.26, 196.0, 165.0, 0.1, 0.55, 0.0),
        ],
    }
}

/// The samples of one sound, as signed 16-bit mono.
///
/// Deterministic down to the noise: the generator is seeded the same way every
/// time, so the same version of this program always writes byte-identical
/// files. Regenerating on every install must not produce something new.
pub fn samples(which: usize) -> Vec<i16> {
    let mut out = Vec::new();
    let mut phase = 0.0f32;
    let mut rng: u32 = 0x1234_5678;
    let mut hold = 0.0f32;
    let mut hold_left = 0.0f32;

    for s in recipe(which) {
        let n = (s.secs * RATE as f32) as usize;
        for i in 0..n {
            let t = if n <= 1 { 0.0 } else { i as f32 / (n - 1) as f32 };
            let freq = s.from + (s.to - s.from) * t;
            let amp = s.amp0 + (s.amp1 - s.amp0) * t;

            phase += freq / RATE as f32;
            if phase >= 1.0 {
                phase -= phase.floor();
            }
            let square = if phase < 0.5 { 1.0 } else { -1.0 };

            // Noise is held for a few samples rather than drawn per sample, so
            // it reads as a crunch at this rate instead of as hiss.
            if hold_left <= 0.0 {
                rng = rng.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                hold = ((rng >> 16) as f32 / 32_768.0) - 1.0;
                hold_left = 6.0;
            }
            hold_left -= 1.0;

            let v = square * (1.0 - s.grit) + hold * s.grit;
            out.push((v * amp * 26_000.0).clamp(-32_000.0, 32_000.0) as i16);
        }
    }
    out
}

/// A mono 16-bit RIFF file. Header, then the samples, little-endian.
pub fn wav(samples: &[i16]) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + data_len as usize);

    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVE");

    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes()); // PCM header length
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM, uncompressed
    out.extend_from_slice(&1u16.to_le_bytes()); // one channel
    out.extend_from_slice(&RATE.to_le_bytes());
    out.extend_from_slice(&(RATE * 2).to_le_bytes()); // bytes per second
    out.extend_from_slice(&2u16.to_le_bytes()); // bytes per frame
    out.extend_from_slice(&16u16.to_le_bytes()); // bits per sample

    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    for s in samples {
        out.extend_from_slice(&s.to_le_bytes());
    }
    out
}

/// Write the whole bank into a directory, as `0-blip.wav` and so on.
pub fn write_bank(dir: &std::path::Path) -> Result<usize, String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("could not make {}: {e}", dir.display()))?;
    for (i, name) in NAMES.iter().enumerate() {
        let path = dir.join(format!("{i}-{name}.wav"));
        let body = wav(&samples(i));
        std::fs::write(&path, &body)
            .map_err(|e| format!("could not write {}: {e}", path.display()))?;
    }
    Ok(NAMES.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn header(b: &[u8], at: usize, tag: &[u8]) -> bool {
        b.len() > at + tag.len() && &b[at..at + tag.len()] == tag
    }

    #[test]
    fn it_is_a_riff_file_a_player_will_accept() {
        let b = wav(&samples(0));
        assert!(header(&b, 0, b"RIFF"), "no RIFF tag");
        assert!(header(&b, 8, b"WAVE"), "no WAVE tag");
        assert!(header(&b, 12, b"fmt "), "no fmt chunk");
        assert!(header(&b, 36, b"data"), "no data chunk");

        // The two lengths in the header have to agree with the actual file, or
        // players either truncate it or read off the end.
        let riff = u32::from_le_bytes(b[4..8].try_into().unwrap());
        let data = u32::from_le_bytes(b[40..44].try_into().unwrap());
        assert_eq!(riff as usize, b.len() - 8, "RIFF length is wrong");
        assert_eq!(data as usize, b.len() - 44, "data length is wrong");
        assert_eq!(data % 2, 0, "16-bit samples cannot be an odd byte count");
    }

    #[test]
    fn every_sound_in_the_bank_makes_a_noise() {
        for i in 0..8 {
            let s = samples(i);
            assert!(!s.is_empty(), "{} generated nothing", NAMES[i]);
            let peak = s.iter().map(|v| v.unsigned_abs()).max().unwrap_or(0);
            assert!(peak > 5_000, "{} is nearly silent (peak {peak})", NAMES[i]);
            // Nothing may clip: a square wave at full scale is already harsh
            // and the headroom is what keeps it from being unbearable.
            assert!(peak < 32_600, "{} clips (peak {peak})", NAMES[i]);
        }
    }

    #[test]
    fn the_bank_is_eight_distinguishable_sounds() {
        // Two entries that generate the same samples means a cart asking for
        // "pickup" and getting "blip", which nobody would notice in code.
        let all: Vec<Vec<i16>> = (0..8).map(samples).collect();
        for i in 0..8 {
            for j in (i + 1)..8 {
                assert_ne!(all[i], all[j], "{} and {} are the same sound", NAMES[i], NAMES[j]);
            }
        }
    }

    #[test]
    fn nothing_in_the_bank_outstays_its_welcome() {
        // These fire on collisions, so several can start in one frame. Anything
        // approaching a second would still be playing over the next ten.
        for i in 0..8 {
            let secs = samples(i).len() as f32 / RATE as f32;
            assert!(secs > 0.02, "{} is too short to hear ({secs}s)", NAMES[i]);
            assert!(secs < 0.7, "{} runs for {secs}s", NAMES[i]);
        }
    }

    #[test]
    fn the_same_version_always_writes_the_same_bytes() {
        // Installing regenerates these. If the noise were seeded from the clock
        // every install would produce different files and every checksum over
        // them would be worthless.
        for i in 0..8 {
            assert_eq!(samples(i), samples(i), "{} is not deterministic", NAMES[i]);
        }
    }

    #[test]
    fn an_index_past_the_bank_wraps_like_a_colour() {
        assert_eq!(samples(8), samples(0));
        assert_eq!(samples(11), samples(3));
    }
}
