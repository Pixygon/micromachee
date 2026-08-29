#version 440
// The glass in front of the panel's screen — the QML twin of web/present.js.
//
// One pass over the composited frame: channel fringing, a cheap bloom halo,
// scanline or LCD-grid structure, grain, and the tube going dark at the
// corners. The numbers arrive per theme from the helper's `status` JSON (the
// same FX table the web reads), and 0 means "not this screen". Persistence is
// the one web effect not done here: it needs frame feedback a single
// ShaderEffect pass cannot have, and a bar widget earns its keep by staying
// one pass.
//
// Compiled with qsb (see shaders/README.md); the .qsb beside this is what QML
// actually loads.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float scanline;
    float bloom;
    float aberration;
    float noise;
    float vignette;
    float grid;
    float time;
    vec2 px;        // one console pixel, in texture coordinates
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 uv = qt_TexCoord0;

    // A shadow mask does not move whole pixels; it lands red and blue a
    // fraction of a pixel apart.
    float ab = aberration * px.x * 0.5;
    vec3 col;
    col.r = texture(source, uv + vec2(-ab, 0.0)).r;
    col.g = texture(source, uv).g;
    col.b = texture(source, uv + vec2(ab, 0.0)).b;

    // Light spilling out of bright neighbours: four taps, one pixel away.
    if (bloom > 0.0) {
        vec3 halo = texture(source, uv + vec2(px.x, 0.0)).rgb
                  + texture(source, uv - vec2(px.x, 0.0)).rgb
                  + texture(source, uv + vec2(0.0, px.y)).rgb
                  + texture(source, uv - vec2(0.0, px.y)).rgb;
        col += halo * 0.25 * bloom * 0.7;
    }

    // The raster: the bottom third of every console row goes dark.
    if (scanline > 0.0) {
        float f = fract(uv.y / px.y);
        if (f > 0.66) col *= 1.0 - scanline;
    }

    // An LCD has cells, so the gap runs both ways and is thin and hard.
    if (grid > 0.0) {
        vec2 f = fract(uv / px);
        if (f.x > 0.8 || f.y > 0.8) col *= 1.0 - grid * 0.55;
    }

    // Grain, one value per console pixel, changing every frame.
    if (noise > 0.0) {
        col += (hash(floor(uv / px) + vec2(fract(time), 0.0)) - 0.5) * 2.0 * noise;
    }

    // The corners falling away.
    if (vignette > 0.0) {
        vec2 d = uv - 0.5;
        float v = smoothstep(0.35, 0.72, length(d * vec2(1.15, 1.0)));
        col *= 1.0 - vignette * v;
    }

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
