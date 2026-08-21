//! The Ydrast tongue.
//!
//! From the Codex: *"strictly rule-based: a small closed grammar, fixed-shape
//! roots, and a deterministic law for new words. Nothing in it is arbitrary
//! twice."* That is a specification, so this is an implementation of it rather
//! than a bag of substitutions.
//!
//! Three rules, in order:
//!
//! 1. **The letters merge.** i and j are one letter; c and q become k; x becomes
//!    ks; the wave-letter w is kept. *"Names cross into the Ydrast by these
//!    mergers alone — Jorvik is written iorvik."* So the merge happens first and
//!    everything downstream sees the merged form, which is why `Jorvik` and
//!    `iorvik` come out as the same word.
//! 2. **The sacred vocabulary is set.** zul, keln, filna, tem, sika, za, morn …
//!    plus the closed set of particles. These are never coined.
//! 3. **The law of new words.** *"A word with no root yet receives one by a
//!    fixed reckoning from its old-reckoning form — the same word always yields
//!    the same root, forever."* So: a hash of the merged form, spent against
//!    fixed sound-tables, giving two or three open syllables. No randomness, no
//!    table of exceptions, and no word ever drifts.
//!
//! Digits are spoken as words — za va te ki fowr sa fi pu me to — so a score of
//! 12 reads *va te*.

/// The sacred vocabulary and the closed grammar. Everything here is attested in
/// the Codex, including the words recovered from THE LIGHTHOUSE's own lines.
const LEXICON: &[(&str, &str)] = &[
    // sacred roots
    ("light", "zul"), ("beam", "zulka"), ("lighthouse", "zultor"),
    ("keeper", "keln"), ("sweep", "svel"), ("paper", "karta"),
    ("time", "tem"), ("thread", "filna"), ("year", "anva"),
    ("sign", "sika"), ("zero", "za"), ("death", "morn"), ("dead", "morn"),
    ("forest", "dremna"), ("verdant", "verna"),
    // recovered from the attested lines
    ("all", "su"), ("that", "ti"), ("remains", "senda"), ("watch", "veln"),
    ("watching", "veln"), ("made", "farn"), ("noted", "skri"),
    ("name", "noma"), ("has", "pon"), ("still", "zel"),
    // the closed grammar
    ("the", "lo"), ("a", "lo"), ("an", "lo"),
    ("is", "zu"), ("are", "zu"), ("am", "zu"), ("be", "zu"),
    ("and", "ye"), ("not", "na"), ("no", "na"),
    ("of", "pe"), ("in", "ne"), ("to", "ka"),
    ("i", "mi"), ("you", "do"), ("your", "do"), ("what", "ma"),
    ("once", "vatem"), ("never", "nazel"),
];

const DIGITS: [&str; 10] = ["za", "va", "te", "ki", "fowr", "sa", "fi", "pu", "me", "to"];

/// Open syllables only: a consonant and a vowel. No c, j, q or x — those merge
/// away by rule 1, so they cannot appear in a root either.
const ONSETS: [&str; 17] = [
    "z", "v", "t", "k", "f", "s", "p", "m", "n", "l", "r", "d", "h", "b", "g", "y", "w",
];
const VOWELS: [&str; 5] = ["a", "e", "i", "o", "u"];

/// The letters of Amebrak. i and j are one letter, c and q become k, x becomes
/// ks, and w swims on.
fn merge_letters(word: &str) -> String {
    let mut out = String::with_capacity(word.len() + 2);
    for ch in word.chars().flat_map(|c| c.to_lowercase()) {
        match ch {
            'j' => out.push('i'),
            'c' | 'q' => out.push('k'),
            'x' => out.push_str("ks"),
            c => out.push(c),
        }
    }
    out
}

/// A fixed reckoning from the old-reckoning form. The same word always yields
/// the same root, forever — so this must never depend on anything but the word.
fn coin(merged: &str) -> String {
    // FNV-1a: small, deterministic, and stable across machines and versions,
    // which "forever" requires.
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in merged.bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    // Two syllables for a short word, three for a longer one: the roots are
    // "two or three open syllables", and letting the length decide keeps a long
    // word from collapsing into something curt.
    let syllables = if merged.chars().count() <= 4 { 2 } else { 3 };
    let mut out = String::with_capacity(syllables * 2);
    for _ in 0..syllables {
        out.push_str(ONSETS[(h % ONSETS.len() as u64) as usize]);
        h /= ONSETS.len() as u64;
        out.push_str(VOWELS[(h % VOWELS.len() as u64) as usize]);
        h /= VOWELS.len() as u64;
        // Re-stir, so the third syllable is not a shadow of the first.
        h = h.wrapping_mul(0x0000_0100_0000_01b3) ^ 0x9e37_79b9_7f4a_7c15;
    }
    out
}

/// One word, in the Ydrast.
pub fn word(w: &str) -> String {
    // The lexicon is looked up as the word is WRITTEN. The mergers are how a
    // name crosses into the tongue, not a step every word passes through first —
    // "watching" contains a c, and merging before the lookup turned an attested
    // word into a coined one.
    let plain: String = w.chars().flat_map(|c| c.to_lowercase()).collect();
    for (english, ydrast) in LEXICON {
        if *english == plain {
            return (*ydrast).to_string();
        }
    }
    // A word with no root yet is reckoned from its old-reckoning form, and that
    // reckoning starts by merging the letters the tongue does not keep.
    coin(&merge_letters(&plain))
}

/// A line of old-reckoning text, rendered in the Ydrast.
///
/// Letters become words; digits become digit-words; everything else — spaces,
/// punctuation, the box-drawing a game does with its own characters — is left
/// exactly where it was, so a HUD still lines up.
pub fn render(text: &str) -> String {
    let mut out = String::with_capacity(text.len() * 2);
    let mut run = String::new();
    let mut run_is_digit = false;

    let flush = |run: &mut String, is_digit: bool, out: &mut String| {
        if run.is_empty() {
            return;
        }
        if is_digit {
            let mut first = true;
            for d in run.chars() {
                if !first {
                    out.push(' ');
                }
                first = false;
                out.push_str(DIGITS[d as usize - '0' as usize]);
            }
        } else {
            out.push_str(&word(run));
        }
        run.clear();
    };

    for ch in text.chars() {
        let is_alpha = ch.is_ascii_alphabetic();
        let is_digit = ch.is_ascii_digit();
        if is_alpha || is_digit {
            if !run.is_empty() && is_digit != run_is_digit {
                flush(&mut run, run_is_digit, &mut out);
            }
            run_is_digit = is_digit;
            run.push(ch);
        } else {
            flush(&mut run, run_is_digit, &mut out);
            out.push(ch);
        }
    }
    flush(&mut run, run_is_digit, &mut out);
    out.to_uppercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_attested_lines_come_out_right() {
        // Straight from the Codex. If the lexicon or the particles drift, these
        // are the lines that catch it — they are canon, not invention.
        assert_eq!(render("the thread is time"), "LO FILNA ZU TEM");
        assert_eq!(render("still watching"), "ZEL VELN");
        assert_eq!(render("all that remains"), "SU TI SENDA");
        assert_eq!(render("all that is made"), "SU TI ZU FARN");
    }

    #[test]
    fn digits_are_spoken_as_words() {
        // "za va te ki fowr sa fi pu me to" for 0 through 9.
        assert_eq!(render("0"), "ZA");
        assert_eq!(render("4"), "FOWR");
        assert_eq!(render("12"), "VA TE");
        assert_eq!(render("SCORE 30"), format!("{} KI ZA", word("score").to_uppercase()));
    }

    #[test]
    fn the_letters_merge_before_anything_else() {
        // "Names cross into the Ydrast by these mergers alone — Jorvik is
        // written iorvik" — so the two must land on the same word.
        assert_eq!(word("Jorvik"), word("iorvik"));
        assert_eq!(word("cat"), word("kat"));
        assert_eq!(word("quay"), word("kuay"));
        assert_eq!(word("box"), word("boks"));
        // and nothing coined may contain a letter the tongue does not have
        for w in ["jump", "exact", "quiz", "cycle", "xylophone"] {
            let r = word(w);
            assert!(!r.contains(['j', 'c', 'q', 'x']), "{w} coined {r}");
        }
    }

    #[test]
    fn a_word_always_yields_the_same_root_forever() {
        // The load-bearing promise of the law of new words.
        for w in ["serpent", "abaddon", "plate", "pixiel", "score"] {
            assert_eq!(word(w), word(w));
            assert_eq!(word(w), word(&w.to_uppercase()));
        }
        // and different words do not collapse onto each other
        let mut seen = std::collections::HashSet::new();
        for w in ["serpent", "abaddon", "plate", "veil", "whale", "signs", "farm", "shaft"] {
            assert!(seen.insert(word(w)), "{w} collided with an earlier root");
        }
    }

    #[test]
    fn roots_are_two_or_three_open_syllables() {
        for w in ["veil", "serpent", "lighthouseкeeper", "a", "abaddon"] {
            let r = word(w);
            assert!(!r.is_empty(), "{w} produced nothing");
            // an open syllable is a consonant then a vowel, so a coined root is
            // always an even number of letters and alternates
            if LEXICON.iter().any(|(_, y)| *y == r) {
                continue; // an attested word keeps its own shape
            }
            assert!(r.len() == 4 || r.len() == 6, "{w} coined {r}, which is not 2 or 3 syllables");
        }
    }

    #[test]
    fn punctuation_and_spacing_survive() {
        // A HUD lines things up with spaces and slashes; the tongue must not
        // rearrange the furniture.
        assert_eq!(render("HP 16/16").matches('/').count(), 1);
        assert!(render("O TO PLANT").starts_with(&word("o").to_uppercase()));
        assert_eq!(render(""), "");
        assert_eq!(render("   "), "   ");
        assert_eq!(render("!!!"), "!!!");
    }
}
