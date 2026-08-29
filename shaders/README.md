# Shaders

`fx.frag` is the glass in front of the panel's screen — the QML twin of
`web/present.js`, driven by the same per-theme numbers (the `fx` object in the
helper's `status` JSON, generated from `helper/src/palettes.rs`).

Qt 6 loads **precompiled** shaders, so the `.qsb` beside the source is what
`Panel.qml` references. After editing `fx.frag`, regenerate and commit both:

```bash
qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o shaders/fx.frag.qsb shaders/fx.frag
```

`qsb` ships with qt6-shadertools. If the `.qsb` fails to load at runtime the
panel falls back to the plain frames — a theme without its glass, never a black
screen.
