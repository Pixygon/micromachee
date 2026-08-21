# Themes

A theme is a **colour mode and a console shell, swapped together**. It repaints
every game ever written for micromachee, including ones written before the theme
existed — so the one thing a theme must not do is make them unreadable.

## Why this is nearly free

A cart says `rect(x, y, w, h, 3)`. It never learns what colour 3 *looks like*.
The palette only becomes real in the `PLTE` chunk of each frame the helper
encodes. Swapping a theme is writing eight different RGB triples into that
chunk: no cost per frame, no change to any cart, and no cart can tell.

That is also the rule cart authors have to keep, stated from their side:

> **A cart indexes colours. It never names them.**
> Nothing may assume slot 2 is red. If a game draws blood it draws it in 2
> because 2 is dark-mid, not because 2 is red.

## The rule a theme must keep

**Preserve the default palette's luminance rank.** Sorted dark to light, the
slots always run:

```
0  <  1  <  2  <  6  <  3  <  5  <  4  <  7
```

Not the *distances* — the **order**. Requiring equal spacing would outlaw every
monochrome theme, and those are the ones worth having. Requiring the order costs
a theme nothing and buys the whole shelf: every contrast a game relies on is
still a contrast. White-on-black text is light-on-ground text in Game Boy green
and in amber; bricks that stepped light-to-dark still step light-to-dark.

A theme that breaks the order — slot 7 darker than slot 0, say — makes every
cart unreadable at once, and **no cart author can do anything about it**, because
they never chose the colours. That is why it is a rule and not a guideline.

Two further checks, for reasons the first rule does not cover:

- **Light on ground is at least 7:1.** Every game prints text on the background.
- **Adjacent ranks stay apart.** Two slots at nearly the same luminance read as
  one colour, which silently costs a game a third of its palette.

`palettes.json` ships only palettes that pass all three.

## How a palette is actually built

Hue per slot is chosen by hand. Brightness is **imposed by arithmetic**, so the
rank holds by construction rather than by eyeballing:

1. Take the default's luminance for each slot, as a position along its ramp.
2. Blend that with even spacing (45%), and map onto the theme's own
   darkest..lightest range. Both curves rise, so any blend of them rises — the
   order cannot break. The blend exists because the default bunches its dark end
   (navy sits at 3% of the range), which is fine across a 19:1 spread and
   collapses two slots on a narrow one.
3. Place each chosen hue at its target luminance by **scaling in linear light**,
   which preserves the hue exactly. Only mix toward white for the shortfall a
   hue physically cannot cover — a saturated blue tops out near L=0.07, which is
   why even the default's blue is a pale sky one.

Step 3 is the one worth not improvising. Mixing toward white *first* is the
obvious implementation and it bleaches every mid slot to beige; it turned the
amber CRT into wet sand and cost the Game Boy its green before it was caught by
looking at a render.

Two consequences worth knowing:

- **The default theme is used verbatim**, not derived. It is the reference the
  others are measured against, and the existing carts are tuned to it.
- **A real Game Boy range is illegal.** `#0f380f`..`#9bbc0f` gives 6:1 and
  collapses slots 0 and 1. The shipped `gameboy` widens both ends. It still
  reads as a Game Boy; it just has a screen you can read eight things on.

## The shell

Shell colours are **derived from the palette**, never picked alongside it, so a
theme cannot drift out of sync with its own chrome and a new palette gets a
matching console body for free.

| key | what it is | from |
|---|---|---|
| `body` | the console around the screen | ground, darkened |
| `bezel` | the frame at the glass | ground |
| `text` | titles, score | slot 7 |
| `dim` | labels, the controls hint | ground↔light, 45% |
| `accent` | records, the active cart | slot 2 |

## Adding one

Add a `(ground, light, [eight hues])` entry, run the generator, and read what it
says. If it fails, it will name the slot and the reason. Then **look at the
carts under it** — the checks catch unreadable, not ugly.
